defmodule Extravaganza.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Extravaganza.BootstrapWorker
    ]

    opts = [strategy: :one_for_one, name: Extravaganza.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
