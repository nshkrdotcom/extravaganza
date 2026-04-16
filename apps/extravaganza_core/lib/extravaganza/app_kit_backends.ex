defmodule Extravaganza.AppKitBackends do
  @moduledoc false

  @backend AppKit.Bridges.MezzanineBridge
  @backend_keys [
    :installation_backend,
    :work_query_backend,
    :work_backend,
    :operator_backend,
    :review_backend
  ]

  @spec ensure_configured() :: :ok
  def ensure_configured do
    Enum.each(@backend_keys, fn key ->
      Application.put_env(:app_kit, key, @backend, persistent: true)
    end)

    :ok
  end
end
