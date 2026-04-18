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
    get("/subjects/:subject_id", PageController, :subject)
    post("/subjects/:subject_id/actions/:action", PageController, :apply_subject_action)
    post("/subjects/:subject_id/read-lease", PageController, :issue_read_lease)
    post("/subjects/:subject_id/stream-attach-lease", PageController, :issue_stream_attach_lease)
    get("/reviews", PageController, :reviews)
    post("/reviews/:decision_id/decisions/:decision", PageController, :record_review_decision)
  end
end
