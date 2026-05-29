defmodule Extravaganza.VirtualServerSupervisor do
  @moduledoc "Supervises Extravaganza virtual-server local processes."
  use Supervisor

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: Supervisor.init([], strategy: :one_for_one)
end
