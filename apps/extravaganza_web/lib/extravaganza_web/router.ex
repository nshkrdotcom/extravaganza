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

  pipeline :api do
    plug(:accepts, ["json"])
    plug(ExtravaganzaWeb.Plugs.AssignCorrelationId)
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

  scope "/api/v1", ExtravaganzaWeb.Api do
    pipe_through(:api)

    get("/state", HeadlessController, :state)
    get("/subjects/:subject_id", HeadlessController, :subject)
    get("/runs/:run_id", HeadlessController, :run)
    post("/refresh", HeadlessController, :refresh)
    post("/subjects/:subject_id/actions/:action", HeadlessController, :control)
    post("/subjects/:subject_id/read-lease", HeadlessController, :read_lease)
    post("/subjects/:subject_id/stream-attach-lease", HeadlessController, :stream_attach_lease)
    get("/reviews", HeadlessController, :reviews)
    post("/reviews/:decision_id/decisions/:decision", HeadlessController, :review_decision)
    get("/:issue_identifier", HeadlessController, :issue_subject)
  end
end
