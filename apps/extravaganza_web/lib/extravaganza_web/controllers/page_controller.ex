defmodule ExtravaganzaWeb.PageController do
  use ExtravaganzaWeb, :controller

  def home(conn, _params) do
    render(conn, :home,
      identity: Extravaganza.identity(),
      mission: Extravaganza.mission(),
      role_label: "proving-ground product"
    )
  end
end
