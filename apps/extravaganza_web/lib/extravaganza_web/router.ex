defmodule ExtravaganzaWeb.Router do
  use ExtravaganzaWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {ExtravaganzaWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", ExtravaganzaWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
    get("/queue", PageController, :queue)
  end
end
