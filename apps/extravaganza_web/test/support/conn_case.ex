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
    sandbox_owners =
      RuntimeStack.repo_modules()
      |> Enum.map(&Sandbox.start_owner!(&1, shared: not tags[:async]))

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
end
