defmodule ExtravaganzaWeb.OperatorConsoleControllerTest do
  use ExtravaganzaWeb.ConnCase, async: false

  test "GET /operator-console renders the AppKit DTO-only console mount", %{conn: conn} do
    body =
      conn
      |> get(~p"/operator-console")
      |> html_response(200)

    assert String.contains?(body, "Operator Console")
    assert String.contains?(body, "dto_and_bounded_exports_only")
    assert String.contains?(body, "app_kit_dtos_no_lower_store_imports")
    assert String.contains?(body, "connector://extravaganza/linear-safe-read")
    refute String.contains?(body, "provider_account_id")
    refute String.contains?(body, "authorization_header")
  end
end
