defmodule ExtravaganzaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :extravaganza_web

  def init(:supervisor, config) do
    config =
      case Keyword.get(config, :headless_server_plan) do
        %{} = plan -> ExtravaganzaWeb.HeadlessServer.endpoint_config(config, plan)
        _missing -> config
      end

    {:ok, config}
  end

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
