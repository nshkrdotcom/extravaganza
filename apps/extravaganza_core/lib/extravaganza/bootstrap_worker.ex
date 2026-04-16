defmodule Extravaganza.BootstrapWorker do
  @moduledoc false

  use GenServer

  alias Extravaganza.ProductBootstrap

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    if Keyword.get(
         opts,
         :enabled?,
         Application.get_env(:extravaganza_core, :bootstrap_on_start?, true)
       ) do
      case ProductBootstrap.ensure_bootstrapped(opts) do
        {:ok, _profile} -> {:ok, opts}
        {:error, reason} -> {:stop, {:bootstrap_failed, reason}}
      end
    else
      {:ok, opts}
    end
  end
end
