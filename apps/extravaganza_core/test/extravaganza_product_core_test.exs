defmodule ExtravaganzaProductCoreTest do
  use ExUnit.Case, async: false

  alias AppKit.Core.RunRef
  alias Ecto.Adapters.SQL.Sandbox
  alias Extravaganza.{Config, LinearIntakeAdapter, ProductBootstrap, ProductPack, ThinHost}
  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.OpsDomain.Repo
  alias Mezzanine.Pack.Compiler

  setup do
    pid = Sandbox.start_owner!(Repo, shared: false)
    tenant_id = "extravaganza-test-#{System.unique_integer([:positive])}"
    pack_version = "1.0.0"

    on_exit(fn -> Sandbox.stop_owner(pid) end)

    {:ok, tenant_id: tenant_id, pack_version: pack_version}
  end

  test "loads normalized config and applies overrides" do
    config =
      Config.load(
        tenant_id: "tenant-override",
        program_name: "Operator Program",
        operator_surface_enabled?: false,
        pack_version: "9.9.9",
        execution_timeout_ms: 123_000
      )

    assert config.tenant_id == "tenant-override"
    assert config.program_name == "Operator Program"
    assert config.operator_surface_enabled? == false
    assert config.program_slug == "extravaganza_coding_ops"
    assert config.pack_version == "9.9.9"
    assert config.execution_timeout_ms == 123_000
  end

  test "bootstrap is idempotent and updates the durable installation profile", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, first} =
             ProductBootstrap.ensure_bootstrapped(
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert {:ok, second} =
             ProductBootstrap.ensure_bootstrapped(
               tenant_id: tenant_id,
               pack_version: pack_version,
               execution_timeout_ms: 180_000
             )

    assert first.installation_ref.id == second.installation_ref.id
    assert first.install_result.status == :created
    assert second.install_result.status in [:reused, :updated]
    assert first.installation_ref.pack_slug == "extravaganza_coding_ops"
    assert second.installation_ref.pack_version == pack_version
    assert second.installation_ref.compiled_pack_revision == 2

    assert get_in(
             second.install_result.metadata.installation.bindings,
             ["execution_bindings", "coding_operations", "execution_params", "timeout_ms"]
           ) == 180_000
  end

  test "linear intake upserts a single work object per external reference", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    issue = %{
      id: "ENG-101",
      identifier: "ENG-101",
      title: "Investigate operator queue",
      description: "Trace queue latency",
      state: "Todo",
      labels: ["ops"],
      team: "Platform",
      url: "https://linear.app/example/issue/ENG-101"
    }

    assert {:ok, first_subject} =
             LinearIntakeAdapter.ingest_issue(
               issue,
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert first_subject.payload.external_ref == "linear:ENG-101"
    assert first_subject.title == "Investigate operator queue"

    updated_issue =
      issue
      |> Map.put(:title, "Investigate operator queue hard failure")
      |> Map.put(:labels, ["ops", "incident"])

    assert {:ok, second_subject} =
             LinearIntakeAdapter.ingest_issue(
               updated_issue,
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert second_subject.subject_ref.id == first_subject.subject_ref.id
    assert second_subject.title == "Investigate operator queue hard failure"
    assert second_subject.payload.external_ref == "linear:ENG-101"
  end

  test "thin host starts a run through the mezzanine-backed app kit path", %{
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    activate_fixture_registration!(tenant_id: tenant_id, pack_version: pack_version)

    assert {:ok, result} =
             ThinHost.start_run(
               %{
                 external_ref: "linear:ENG-202",
                 title: "Ship operator shell slice",
                 description: "Drive the thin-host path",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-202"},
                 normalized_payload: %{"issue_id" => "ENG-202"}
               },
               tenant_id: tenant_id,
               pack_version: pack_version
             )

    assert result.surface == :work_control
    assert result.state == :waiting_review
    assert %RunRef{} = result.payload.run_ref
    assert result.payload.run_ref.metadata.tenant_id == tenant_id
    assert is_binary(result.payload.work_object_id)

    assert {:ok, status} = ThinHost.run_status(result.payload.run_ref, %{}, tenant_id: tenant_id)

    assert status.work_object_id == result.payload.work_object_id
    assert is_list(status.timeline)
    assert is_map(status.gate_status)
  end

  defp activate_fixture_registration!(opts) do
    pack_slug = ProductPack.pack_slug(opts)
    pack_version = ProductPack.pack_version(opts)

    case PackRegistration.by_slug_version(pack_slug, pack_version) do
      {:ok, %PackRegistration{status: :active}} ->
        :ok

      {:ok, %PackRegistration{} = registration} ->
        assert {:ok, %PackRegistration{status: :active}} = PackRegistration.activate(registration)

      {:error, _reason} ->
        {:ok, compiled_pack} =
          opts
          |> ProductPack.manifest()
          |> Compiler.compile()

        registration = MezzanineConfigRegistry.register_pack!(compiled_pack)
        assert {:ok, %PackRegistration{status: :active}} = PackRegistration.activate(registration)
    end
  end
end
