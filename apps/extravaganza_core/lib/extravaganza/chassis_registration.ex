defmodule Extravaganza.ChassisRegistration do
  @moduledoc "Registers Extravaganza with AppKit.SpatialGateway when Chassis is present."
  use GenServer

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    {:ok, Keyword.put(opts, :profile_ref, active_profile())}
  end

  @spec active_profile() :: String.t()
  def active_profile do
    spatial_gateway = Module.concat([AppKit, SpatialGateway])

    if Code.ensure_loaded?(spatial_gateway) and
         function_exported?(spatial_gateway, :get_active_profile, 0) do
      case spatial_gateway.get_active_profile() do
        {:ok, %{profile_ref: profile_ref}} -> profile_ref
        _other -> "profile:monolith"
      end
    else
      "profile:monolith"
    end
  end
end
