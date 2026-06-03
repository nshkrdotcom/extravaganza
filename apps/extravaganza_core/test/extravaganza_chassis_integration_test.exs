defmodule Extravaganza.ChassisIntegrationTest do
  use ExUnit.Case, async: false

  alias AppKit.SpatialGateway.Request

  @all_virtual_servers [
    :vs_app_kit,
    :vs_mezzanine,
    :vs_outer_brain,
    :vs_citadel,
    :vs_jido_integration,
    :vs_execution_plane,
    :vs_secrets_plane,
    :vs_observability
  ]

  defmodule SpatialBackend do
    def handle(%Request.GetActiveProfile{}, opts) do
      {:ok, Keyword.fetch!(opts, :active_profile)}
    end

    def handle(%Request.RegisterDeployedApp{} = request, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:registered, request, opts})
      {:ok, "receipt:appkit:extravaganza:test"}
    end
  end

  defmodule StandaloneBackend do
    def handle(%Request.GetActiveProfile{}, _opts), do: {:ok, "profile:monolith"}
    def handle(%Request.RegisterDeployedApp{}, _opts), do: {:error, :standalone}
  end

  defmodule TestChild do
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
    def init(opts), do: {:ok, opts}
  end

  setup do
    previous = Application.get_env(:extravaganza_core, :installation_ref)
    Application.put_env(:extravaganza_core, :installation_ref, "installation:extravaganza:test")

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:extravaganza_core, :installation_ref)
      else
        Application.put_env(:extravaganza_core, :installation_ref, previous)
      end
    end)
  end

  test "registration reads active profile through SpatialGateway and registers the bootstrapped installation" do
    assert {:ok, state} =
             Extravaganza.ChassisRegistration.register(
               app_atom: :extravaganza,
               active_profile: "profile:ternary-split-3",
               spatial_gateway_backend: SpatialBackend,
               test_pid: self(),
               tenant_ref: "tenant:acme",
               release_sha: "abc123",
               release_version: "0.1.0",
               environment: :prod
             )

    assert state.receipt_ref == "receipt:appkit:extravaganza:test"
    assert state.profile_ref == "profile:ternary-split-3"

    assert_receive {:registered, request, opts}
    assert request.app_atom == :extravaganza
    assert request.git_sha == "abc123"
    assert opts[:profile_ref] == "profile:ternary-split-3"
    assert opts[:installation_ref] == "installation:extravaganza:test"
    assert opts[:tenant_ref] == "tenant:acme"
    assert opts[:environment] == :prod
  end

  test "registration fails open only for the explicit standalone backend result" do
    assert {:ok, state} =
             Extravaganza.ChassisRegistration.register(
               spatial_gateway_backend: StandaloneBackend,
               release_sha: "abc123"
             )

    assert state.standalone == true
    assert state.profile_ref == "profile:monolith"
  end

  test "topology resolves Chassis profile placements by node pattern" do
    assert {:ok, servers} =
             Extravaganza.Topology.virtual_servers_for(
               :extravaganza,
               "profile:monolith",
               :"monolith@127.0.0.1"
             )

    assert Enum.sort(servers) == Enum.sort(@all_virtual_servers)

    assert {:ok, [:vs_mezzanine, :vs_citadel, :vs_secrets_plane]} =
             Extravaganza.Topology.virtual_servers_for(
               :extravaganza,
               "profile:ternary-split-3",
               :control@vps2
             )

    assert {:ok, [:vs_outer_brain, :vs_jido_integration, :vs_execution_plane]} =
             Extravaganza.Topology.virtual_servers_for(
               :extravaganza,
               "profile:ternary-split-3",
               :data@vps3
             )

    assert {:error, :unknown_profile} =
             Extravaganza.Topology.virtual_servers_for(
               :extravaganza,
               "profile:nope",
               :data@vps3
             )
  end

  test "virtual server supervisor boots child specs for the resolved profile" do
    assert {:ok, {_, children}} =
             Extravaganza.VirtualServerSupervisor.init(
               app_atom: :extravaganza,
               active_profile: "profile:ternary-split-3",
               node: :appkit@vps1,
               spatial_gateway_backend: SpatialBackend,
               child_specs: %{vs_app_kit: [{TestChild, name: :appkit_child}]},
               test_pid: self()
             )

    assert [
             %{
               id: TestChild,
               start: {TestChild, :start_link, [[name: :appkit_child]]}
             }
           ] = children
  end

  test "profile manifests contain service specs with virtual server placement" do
    root = Path.expand("../priv/chassis_profiles", __DIR__)

    for file <- ~w(monolith decoupled_cockpit_2 ternary_split_3 maximal_decoupled) do
      manifest = root |> Path.join(file <> ".json") |> File.read!() |> Jason.decode!()

      assert manifest["app_atom"] == "extravaganza"
      assert is_binary(manifest["profile_ref"])
      assert [_ | _] = manifest["service_specs"]

      assert Enum.all?(manifest["service_specs"], fn service ->
               is_binary(service["service_spec_ref"]) and
                 is_binary(service["node_name_pattern"]) and
                 is_binary(service["systemd_unit_name"]) and
                 match?([_ | _], service["virtual_servers"])
             end)
    end
  end
end
