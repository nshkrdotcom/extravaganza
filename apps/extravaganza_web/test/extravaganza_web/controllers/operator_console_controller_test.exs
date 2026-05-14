defmodule ExtravaganzaWeb.OperatorConsoleControllerTest do
  use ExtravaganzaWeb.ConnCase, async: false

  alias Extravaganza.TestSupport.FakeHeadlessBackend

  setup do
    previous_backend = Application.get_env(:app_kit_core, :headless_backend)
    previous_fixture_context = Application.get_env(:extravaganza_core, :headless_fixture_context?)

    Application.put_env(:app_kit_core, :headless_backend, FakeHeadlessBackend)
    Application.put_env(:extravaganza_core, :headless_fixture_context?, true)

    on_exit(fn ->
      if previous_backend do
        Application.put_env(:app_kit_core, :headless_backend, previous_backend)
      else
        Application.delete_env(:app_kit_core, :headless_backend)
      end

      if is_nil(previous_fixture_context) do
        Application.delete_env(:extravaganza_core, :headless_fixture_context?)
      else
        Application.put_env(
          :extravaganza_core,
          :headless_fixture_context?,
          previous_fixture_context
        )
      end
    end)
  end

  test "GET /operator-console renders the AppKit DTO-only console mount", %{conn: conn} do
    body =
      conn
      |> get(~p"/operator-console")
      |> html_response(200)

    assert String.contains?(body, "Operator Console")
    assert String.contains?(body, "dto_and_bounded_exports_only")
    assert String.contains?(body, "app_kit_dtos_no_lower_store_imports")
    assert String.contains?(body, "connector://extravaganza/linear-safe-read")
    assert String.contains?(body, "Runtime Dashboard")
    assert String.contains?(body, "Running")
    assert String.contains?(body, "Retrying")
    assert String.contains?(body, "Completed")
    assert String.contains?(body, "Total Tokens")
    assert String.contains?(body, "1,650")
    assert String.contains?(body, "0.00 tps")
    assert String.contains?(body, "rate:codex:minute")
    assert String.contains?(body, "session:running")
    assert String.contains?(body, "fixture turn completed")
    assert String.contains?(body, ~s(data-observability-stream="/operator-console/updates"))
    assert String.contains?(body, "EventSource")
    assert String.contains?(body, "headless-observability-updated")
    refute String.contains?(body, "provider_account_id")
    refute String.contains?(body, "authorization_header")
    refute String.contains?(body, "workspace_path")
    refute String.contains?(body, "/home/")
  end

  test "GET /operator-console/updates streams a safe ready event", %{conn: conn} do
    conn = get(conn, ~p"/operator-console/updates?once=true")
    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["text/event-stream; charset=utf-8"]
    assert String.contains?(body, "event: ready")
    assert String.contains?(body, "headless_observability_ready")
    assert String.contains?(body, "headless_observability_update.v1")
    refute String.contains?(body, "authorization_header")
    refute String.contains?(body, "workspace_path")
    refute String.contains?(body, "/home/")
  end
end
