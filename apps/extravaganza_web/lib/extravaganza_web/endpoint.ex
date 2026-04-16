defmodule ExtravaganzaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :extravaganza_web

  @session_options [
    store: :cookie,
    key: "_extravaganza_web_key",
    signing_salt: "thin-shell"
  ]

  if code_reloading? do
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(ExtravaganzaWeb.Router)
end
