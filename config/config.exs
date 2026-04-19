import Config

config :app_kit_core,
  installation_backend: AppKit.Bridges.MezzanineBridge,
  work_query_backend: AppKit.Bridges.MezzanineBridge,
  work_backend: AppKit.Bridges.MezzanineBridge,
  operator_backend: AppKit.Bridges.MezzanineBridge,
  review_backend: AppKit.Bridges.MezzanineBridge

config :extravaganza_web, ExtravaganzaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: ExtravaganzaWeb.ErrorHTML], layout: false],
  pubsub_server: ExtravaganzaWeb.PubSub

config :phoenix, :json_library, Jason

config :mezzanine_audit_engine,
  ecto_repos: [Mezzanine.Audit.Repo],
  ash_domains: [Mezzanine.Audit]

config :mezzanine_object_engine,
  ecto_repos: [Mezzanine.Objects.Repo],
  ash_domains: [Mezzanine.Objects]

config :mezzanine_execution_engine,
  ecto_repos: [Mezzanine.Execution.Repo],
  ash_domains: [Mezzanine.Execution]

config :mezzanine_execution_engine, Oban,
  name: Mezzanine.Execution.Oban,
  repo: Mezzanine.Execution.Repo,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  peer: false,
  queues: [workflow_start_outbox: 10, workflow_signal_outbox: 10, claim_check_gc: 2],
  plugins: []

config :mezzanine_decision_engine,
  ecto_repos: [Mezzanine.Decisions.Repo],
  ash_domains: [Mezzanine.Decisions]

config :mezzanine_evidence_engine,
  ecto_repos: [Mezzanine.EvidenceLedger.Repo],
  ash_domains: [Mezzanine.EvidenceLedger]

config :mezzanine_archival_engine,
  ecto_repos: [Mezzanine.Archival.Repo],
  ash_domains: [Mezzanine.Archival],
  start_runtime_children?: true,
  cold_store: [
    module: Mezzanine.Archival.FileSystemColdStore,
    root: Path.join(System.tmp_dir!(), "extravaganza_archival_store")
  ],
  scheduler: [
    enabled?: false,
    interval_ms: :timer.minutes(5)
  ]

config :mezzanine_config_registry,
  ecto_repos: [Mezzanine.ConfigRegistry.Repo],
  ash_domains: [Mezzanine.ConfigRegistry]

config :extravaganza_core, Extravaganza.Config,
  tenant_id: "extravaganza",
  program_slug: "extravaganza_coding_ops",
  program_name: "Extravaganza Coding Operations",
  product_family: "extravaganza",
  pack_version: "1.0.0",
  policy_bundle_name: "default_coding_ops",
  policy_bundle_version: "1.0.0",
  work_class_name: "coding_operations",
  work_class_kind: "coding_task",
  placement_profile_id: "local_default",
  execution_timeout_ms: 300_000,
  linear_source_kind: "linear",
  operator_surface_enabled?: true

config :extravaganza_core,
  bootstrap_on_start?: true,
  linear_polling_enabled?: false

import_config "#{config_env()}.exs"
