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

  pipeline :event_stream do
    plug(:fetch_session)
    plug(:put_secure_browser_headers)
  end

  scope "/", ExtravaganzaWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
    get("/queue", PageController, :queue)
    get("/operator-console", PageController, :operator_console)
    get("/subjects/:subject_id", PageController, :subject)
    post("/subjects/:subject_id/actions/:action", PageController, :apply_subject_action)
    post("/subjects/:subject_id/read-lease", PageController, :issue_read_lease)
    post("/subjects/:subject_id/stream-attach-lease", PageController, :issue_stream_attach_lease)
    get("/reviews", PageController, :reviews)
    post("/reviews/:decision_id/decisions/:decision", PageController, :record_review_decision)
  end

  scope "/", ExtravaganzaWeb do
    pipe_through(:event_stream)

    get("/operator-console/updates", PageController, :operator_console_updates)
  end

  scope "/api/v1", ExtravaganzaWeb.Api do
    pipe_through(:api)

    get("/state", HeadlessController, :state)
    match(:*, "/state", HeadlessController, :method_not_allowed)

    get("/status", HeadlessController, :status)
    match(:*, "/status", HeadlessController, :method_not_allowed)

    get("/logs", HeadlessController, :logs)
    match(:*, "/logs", HeadlessController, :method_not_allowed)

    get("/profile", HeadlessController, :profile)
    match(:*, "/profile", HeadlessController, :method_not_allowed)

    post("/profile/validate", HeadlessController, :profile_validate)
    match(:*, "/profile/validate", HeadlessController, :method_not_allowed)

    post("/profile/reload", HeadlessController, :profile_reload)
    match(:*, "/profile/reload", HeadlessController, :method_not_allowed)

    post("/source-publication", HeadlessController, :source_publish)
    match(:*, "/source-publication", HeadlessController, :method_not_allowed)

    post("/live/linear-source", HeadlessController, :live_linear_source)
    match(:*, "/live/linear-source", HeadlessController, :method_not_allowed)

    post("/live/linear-current-states", HeadlessController, :live_linear_current_states)
    match(:*, "/live/linear-current-states", HeadlessController, :method_not_allowed)

    post("/live/codex-turn", HeadlessController, :live_codex_turn)
    match(:*, "/live/codex-turn", HeadlessController, :method_not_allowed)

    post("/live/linear-publication", HeadlessController, :live_linear_publication)
    match(:*, "/live/linear-publication", HeadlessController, :method_not_allowed)

    post("/live/linear-graphql-tool", HeadlessController, :live_linear_graphql_tool)
    match(:*, "/live/linear-graphql-tool", HeadlessController, :method_not_allowed)

    post("/live/github-evidence", HeadlessController, :live_github_evidence)
    match(:*, "/live/github-evidence", HeadlessController, :method_not_allowed)

    post("/live/github-pr-cleanup", HeadlessController, :live_github_pr_cleanup)
    match(:*, "/live/github-pr-cleanup", HeadlessController, :method_not_allowed)

    post("/live/smoke", HeadlessController, :live_smoke)
    match(:*, "/live/smoke", HeadlessController, :method_not_allowed)

    get("/subjects/:subject_id", HeadlessController, :subject)
    match(:*, "/subjects/:subject_id", HeadlessController, :method_not_allowed)

    get("/subjects/:subject_id/source-publication", HeadlessController, :source_publication)
    post("/subjects/:subject_id/source-publication", HeadlessController, :source_publish)
    match(:*, "/subjects/:subject_id/source-publication", HeadlessController, :method_not_allowed)

    get("/runs/:run_id", HeadlessController, :run)
    match(:*, "/runs/:run_id", HeadlessController, :method_not_allowed)

    get("/runs/:run_id/evidence", HeadlessController, :evidence)
    match(:*, "/runs/:run_id/evidence", HeadlessController, :method_not_allowed)

    get("/events", HeadlessController, :events)
    match(:*, "/events", HeadlessController, :method_not_allowed)

    post("/refresh", HeadlessController, :refresh)
    match(:*, "/refresh", HeadlessController, :method_not_allowed)

    post("/subjects/:subject_id/actions/:action", HeadlessController, :control)
    match(:*, "/subjects/:subject_id/actions/:action", HeadlessController, :method_not_allowed)

    post("/subjects/:subject_id/control/:action", HeadlessController, :control)
    match(:*, "/subjects/:subject_id/control/:action", HeadlessController, :method_not_allowed)

    post("/subjects/:subject_id/read-lease", HeadlessController, :read_lease)
    match(:*, "/subjects/:subject_id/read-lease", HeadlessController, :method_not_allowed)

    post("/subjects/:subject_id/stream-attach-lease", HeadlessController, :stream_attach_lease)

    match(
      :*,
      "/subjects/:subject_id/stream-attach-lease",
      HeadlessController,
      :method_not_allowed
    )

    get("/reviews", HeadlessController, :reviews)
    match(:*, "/reviews", HeadlessController, :method_not_allowed)

    post("/reviews/:decision_id/decisions/:decision", HeadlessController, :review_decision)

    match(
      :*,
      "/reviews/:decision_id/decisions/:decision",
      HeadlessController,
      :method_not_allowed
    )

    get("/:issue_identifier", HeadlessController, :issue_subject)
    match(:*, "/:issue_identifier", HeadlessController, :method_not_allowed)
    match(:*, "/*path", HeadlessController, :not_found)
  end
end
