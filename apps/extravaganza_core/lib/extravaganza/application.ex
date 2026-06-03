defmodule Extravaganza.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      configured_repo_children() ++
        [
          Extravaganza.BootstrapWorker,
          {Extravaganza.ChassisRegistration, app_atom: :extravaganza},
          {Extravaganza.VirtualServerSupervisor, app_atom: :extravaganza}
        ]

    opts = [strategy: :rest_for_one, name: Extravaganza.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp configured_repo_children do
    :extravaganza_core
    |> Application.get_env(:ecto_repos, [])
    |> Enum.uniq()
    |> Enum.reject(&repo_started?/1)
    |> Enum.map(&{&1, []})
  end

  defp repo_started?(repo), do: is_pid(Process.whereis(repo))
end
