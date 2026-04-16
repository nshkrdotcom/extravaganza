defmodule ExtravaganzaWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Extravaganza.Config
  alias Mezzanine.OpsDomain.Repo

  using do
    quote do
      @endpoint ExtravaganzaWeb.Endpoint

      use ExtravaganzaWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
    end
  end

  setup tags do
    sandbox_owner = Sandbox.start_owner!(Repo, shared: not tags[:async])
    tenant_id = "extravaganza-web-test-#{System.unique_integer([:positive])}"
    pack_version = "1.0.0"
    previous_config = Application.get_env(:extravaganza_core, Config, [])

    Application.put_env(
      :extravaganza_core,
      Config,
      Keyword.merge(previous_config, tenant_id: tenant_id, pack_version: pack_version)
    )

    on_exit(fn ->
      Application.put_env(:extravaganza_core, Config, previous_config)
      Sandbox.stop_owner(sandbox_owner)
    end)

    {:ok, conn: Phoenix.ConnTest.build_conn(), tenant_id: tenant_id, pack_version: pack_version}
  end
end
