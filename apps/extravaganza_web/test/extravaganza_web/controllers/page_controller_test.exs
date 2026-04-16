defmodule ExtravaganzaWeb.PageControllerTest do
  use ExtravaganzaWeb.ConnCase, async: true

  test "GET / renders the product shell", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~ "Extravaganza"
    assert html_response(conn, 200) =~ "proving-ground product"
  end
end
