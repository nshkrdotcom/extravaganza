import Config

config :mezzanine_ops_domain, Mezzanine.OpsDomain.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mezzanine_ops_domain_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :extravaganza_web, ExtravaganzaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "3oS1b1kV9mM9nF5zY8rT2cH6pQ4uL7aN2xW5jD8sK1mP6vB9qR3tY7uI4oP8lA2"

config :phoenix, :plug_init_mode, :runtime
