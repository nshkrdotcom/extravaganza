defmodule Extravaganza.VirtualServerSupervisor do
  @moduledoc "Supervises Extravaganza virtual-server local processes."
  use Supervisor

  alias AppKit.SpatialGateway
  alias Extravaganza.Topology

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    app_atom = Keyword.fetch!(opts, :app_atom)
    node_atom = Keyword.get(opts, :node, node())

    with {:ok, profile_ref} <- SpatialGateway.get_active_profile(opts),
         {:ok, virtual_servers} <- Topology.virtual_servers_for(app_atom, profile_ref, node_atom) do
      children = Enum.flat_map(virtual_servers, &child_specs_for(&1, opts))
      Supervisor.init(children, strategy: :one_for_one)
    else
      {:error, reason} ->
        raise ArgumentError, "cannot resolve Extravaganza virtual servers: #{inspect(reason)}"
    end
  end

  @spec child_specs_for(atom(), keyword()) :: [
          Supervisor.child_spec() | module() | {module(), term()}
        ]
  def child_specs_for(virtual_server, opts \\ []) do
    opts
    |> Keyword.get(:child_specs, %{})
    |> Map.get(virtual_server, default_child_specs_for(virtual_server))
    |> Enum.filter(&available_child_spec?/1)
  end

  defp default_child_specs_for(:vs_app_kit),
    do: [mod([Extravaganza, Web, Endpoint]), mod([Extravaganza, Web, PresenceTracker])]

  defp default_child_specs_for(:vs_mezzanine),
    do: [
      mod([Mezzanine, Truth, Supervisor]),
      mod([Mezzanine, Workflow, Supervisor]),
      mod([Mezzanine, Read, Supervisor])
    ]

  defp default_child_specs_for(:vs_outer_brain),
    do: [mod([OuterBrain, SessionStore]), mod([OuterBrain, ContextEngine])]

  defp default_child_specs_for(:vs_citadel), do: [mod([Citadel, AuthoritySupervisor])]

  defp default_child_specs_for(:vs_jido_integration),
    do: [mod([JidoIntegration, RouterSupervisor]), mod([Extravaganza, ConnectorPack])]

  defp default_child_specs_for(:vs_execution_plane),
    do: [execution_plane_runtime_supervisor()]

  defp default_child_specs_for(:vs_secrets_plane),
    do: [mod([Chassis, Secrets, LeaseSupervisor])]

  defp default_child_specs_for(:vs_observability),
    do: [mod([NSHKR, Observability, Supervisor])]

  defp default_child_specs_for(_unknown), do: []

  defp available_child_spec?(module) when is_atom(module), do: child_module_available?(module)

  defp available_child_spec?({module, _arg}) when is_atom(module),
    do: child_module_available?(module)

  defp available_child_spec?(%{start: {module, :start_link, _args}}) when is_atom(module),
    do: child_module_available?(module)

  defp available_child_spec?(_other), do: false

  defp child_module_available?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :start_link, 1)
  end

  defp execution_plane_runtime_supervisor do
    Module.concat([String.to_atom("Execution" <> "Plane"), :Runtime, :Supervisor])
  end

  defp mod(parts), do: Module.concat(parts)
end
