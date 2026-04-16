defmodule Extravaganza.Application do
  @moduledoc false

  use Application

  alias Extravaganza.AppKitBackends

  @impl true
  def start(_type, _args) do
    :ok = AppKitBackends.ensure_configured()

    children = [
      Extravaganza.BootstrapWorker
    ]

    opts = [strategy: :one_for_one, name: Extravaganza.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
