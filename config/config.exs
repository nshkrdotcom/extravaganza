import Config

config :ash,
  domains: [
    Mezzanine.Audit,
    Mezzanine.ConfigRegistry,
    Mezzanine.Objects,
    Mezzanine.Execution,
    Mezzanine.Decisions,
    Mezzanine.Programs,
    Mezzanine.Work,
    Mezzanine.Runs,
    Mezzanine.Review,
    Mezzanine.Evidence,
    Mezzanine.Control,
    Mezzanine.EvidenceLedger
  ]

config :extravaganza_core,
  ecto_repos: [
    Mezzanine.Audit.Repo,
    Mezzanine.ConfigRegistry.Repo,
    Mezzanine.Objects.Repo,
    Mezzanine.Execution.Repo,
    Mezzanine.Decisions.Repo,
    Mezzanine.EvidenceLedger.Repo,
    Mezzanine.OpsDomain.Repo
  ]

config :mezzanine_audit_engine,
  ecto_repos: [Mezzanine.Audit.Repo],
  ash_domains: [Mezzanine.Audit]

config :mezzanine_object_engine,
  ecto_repos: [Mezzanine.Objects.Repo],
  ash_domains: [Mezzanine.Objects]

config :mezzanine_execution_engine,
  ecto_repos: [Mezzanine.Execution.Repo],
  ash_domains: [Mezzanine.Execution]

config :mezzanine_decision_engine,
  ecto_repos: [Mezzanine.Decisions.Repo],
  ash_domains: [Mezzanine.Decisions]

config :mezzanine_evidence_engine,
  ecto_repos: [Mezzanine.EvidenceLedger.Repo],
  ash_domains: [Mezzanine.EvidenceLedger]

config :mezzanine_config_registry,
  ecto_repos: [Mezzanine.ConfigRegistry.Repo],
  ash_domains: [Mezzanine.ConfigRegistry]

config :mezzanine_ops_domain,
  ecto_repos: [Mezzanine.OpsDomain.Repo],
  ash_domains: [
    Mezzanine.Programs,
    Mezzanine.Work,
    Mezzanine.Runs,
    Mezzanine.Review,
    Mezzanine.Evidence,
    Mezzanine.Control
  ]

config :mezzanine_app_kit_bridge,
  ecto_repos: [
    Mezzanine.Audit.Repo,
    Mezzanine.ConfigRegistry.Repo,
    Mezzanine.Objects.Repo,
    Mezzanine.Execution.Repo,
    Mezzanine.Decisions.Repo,
    Mezzanine.EvidenceLedger.Repo,
    Mezzanine.OpsDomain.Repo
  ]

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
