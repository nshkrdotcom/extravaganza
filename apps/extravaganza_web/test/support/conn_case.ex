defmodule ExtravaganzaWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Extravaganza.Config
  alias Mezzanine.Execution.RuntimeStack

  using do
    quote do
      @endpoint ExtravaganzaWeb.Endpoint

      use ExtravaganzaWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
    end
  end

  setup tags do
    shared? = not tags[:async]

    repos = RuntimeStack.repo_modules()

    ensure_repos_started(repos)

    sandbox_owners =
      repos
      |> Enum.map(&{&1, [shared: shared?]})
      |> start_sandbox_owners()

    test_suffix = "#{System.system_time(:nanosecond)}_#{System.unique_integer([:positive])}"
    version_suffix = String.replace(test_suffix, "_", ".")
    tenant_id = "extravaganza-web-test-#{Ecto.UUID.generate()}"
    pack_version = "1.0.0-test.#{version_suffix}"
    previous_config = Application.get_env(:extravaganza_core, Config, [])

    Application.put_env(
      :extravaganza_core,
      Config,
      Keyword.merge(previous_config,
        tenant_id: tenant_id,
        pack_version: pack_version
      )
    )

    on_exit(fn ->
      Application.put_env(:extravaganza_core, Config, previous_config)
      Enum.each(sandbox_owners, &Sandbox.stop_owner/1)
    end)

    {:ok, conn: Phoenix.ConnTest.build_conn(), tenant_id: tenant_id, pack_version: pack_version}
  end

  defp ensure_repos_started(repos) do
    Enum.each(repos, fn repo ->
      case repo.start_link() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end
    end)
  end

  defp start_sandbox_owners(repo_specs) do
    do_start_sandbox_owners(repo_specs, [])
  end

  defp do_start_sandbox_owners([], owners), do: Enum.reverse(owners)

  defp do_start_sandbox_owners([{repo, opts} | rest], owners) do
    owner = Sandbox.start_owner!(repo, opts)
    do_start_sandbox_owners(rest, [owner | owners])
  rescue
    exception ->
      Enum.each(owners, &Sandbox.stop_owner/1)
      reraise exception, __STACKTRACE__
  end
end
