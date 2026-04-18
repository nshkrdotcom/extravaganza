import Config

config :mezzanine_audit_engine, Mezzanine.Audit.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mezzanine_app_kit_bridge_substrate_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

config :mezzanine_config_registry, Mezzanine.ConfigRegistry.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mezzanine_config_registry_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

config :mezzanine_object_engine, Mezzanine.Objects.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mezzanine_app_kit_bridge_substrate_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

config :mezzanine_execution_engine, Mezzanine.Execution.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mezzanine_app_kit_bridge_substrate_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

config :mezzanine_execution_engine, Oban,
  name: Mezzanine.Execution.Oban,
  repo: Mezzanine.Execution.Repo,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  peer: false,
  queues: false,
  plugins: false,
  testing: :manual

config :mezzanine_decision_engine, Mezzanine.Decisions.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mezzanine_app_kit_bridge_substrate_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

config :mezzanine_evidence_engine, Mezzanine.EvidenceLedger.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mezzanine_app_kit_bridge_substrate_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

config :extravaganza_core,
  bootstrap_on_start?: false,
  linear_polling_enabled?: false

config :extravaganza_web, ExtravaganzaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "7pN4vD2mL9xQ5rH1cK8sT3yB6uF0aW4jE7nR2qM5zP8vX1cL4tG9hJ6kS3dF0bN7",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
