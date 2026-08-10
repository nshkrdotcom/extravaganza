repo_root = Path.expand("..", __DIR__)
siblings_root = Path.expand("..", repo_root)

dep = fn repo, subdir, hex ->
  %{
    path: Path.join(siblings_root, "#{repo}/#{subdir}"),
    github: %{repo: "nshkrdotcom/#{repo}", branch: "main", subdir: subdir},
    hex: hex,
    opts: [override: true],
    default_order: [:path, :github, :hex],
    publish_order: [:hex]
  }
end

%{
  deps: %{
    ai_trace_replay_contracts: dep.("AITrace", "core/replay_contracts", "~> 0.1.0"),
    app_kit_app_config: dep.("app_kit", "core/app_config", "~> 0.1.0"),
    app_kit_budget_surface: dep.("app_kit", "core/budget_surface", "~> 0.1.0"),
    app_kit_context_surface: dep.("app_kit", "core/context_surface", "~> 0.1.0"),
    app_kit_cost_dashboard: dep.("app_kit", "web/cost_dashboard", "~> 0.1.0"),
    app_kit_cost_surface: dep.("app_kit", "core/cost_surface", "~> 0.1.0"),
    app_kit_core: dep.("app_kit", "core/app_kit_core", "~> 0.1.0"),
    app_kit_chassis_bridge: dep.("app_kit", "bridges/chassis_bridge", "~> 0.1.0"),
    app_kit_eval_studio: dep.("app_kit", "web/eval_studio", "~> 0.1.0"),
    app_kit_eval_surface: dep.("app_kit", "core/eval_surface", "~> 0.1.0"),
    app_kit_guardrail_surface: dep.("app_kit", "core/guardrail_surface", "~> 0.1.0"),
    app_kit_installation_surface: dep.("app_kit", "core/installation_surface", "~> 0.1.0"),
    app_kit_integration_bridge: dep.("app_kit", "bridges/integration_bridge", "~> 0.1.0"),
    app_kit_memory_surface: dep.("app_kit", "core/memory_surface", "~> 0.1.0"),
    app_kit_mezzanine_bridge: dep.("app_kit", "bridges/mezzanine_bridge", "~> 0.1.0"),
    app_kit_operator_console: dep.("app_kit", "web/operator_console", "~> 0.1.0"),
    app_kit_operator_surface: dep.("app_kit", "core/operator_surface", "~> 0.1.0"),
    app_kit_policy_authoring: dep.("app_kit", "web/policy_authoring", "~> 0.1.0"),
    app_kit_projection_bridge: dep.("app_kit", "bridges/projection_bridge", "~> 0.1.0"),
    app_kit_prompt_surface: dep.("app_kit", "core/prompt_surface", "~> 0.1.0"),
    app_kit_replay_surface: dep.("app_kit", "core/replay_surface", "~> 0.1.0"),
    app_kit_replay_viewer: dep.("app_kit", "web/replay_viewer", "~> 0.1.0"),
    app_kit_review_surface: dep.("app_kit", "core/review_surface", "~> 0.1.0"),
    app_kit_run_governance: dep.("app_kit", "core/run_governance", "~> 0.1.0"),
    app_kit_runtime_gateway: dep.("app_kit", "core/runtime_gateway", "~> 0.1.0"),
    app_kit_scope_objects: dep.("app_kit", "core/scope_objects", "~> 0.1.0"),
    app_kit_web_components: dep.("app_kit", "web/components", "~> 0.1.0"),
    app_kit_work_control: dep.("app_kit", "core/work_control", "~> 0.1.0"),
    app_kit_work_surface: dep.("app_kit", "core/work_surface", "~> 0.1.0"),
    citadel_authority_contract: dep.("citadel", "core/authority_contract", "~> 0.1.0"),
    citadel_contract_core: dep.("citadel", "core/contract_core", "~> 0.1.0"),
    citadel_domain_surface: dep.("citadel", "surfaces/citadel_domain_surface", "~> 0.1.0"),
    citadel_execution_governance_contract:
      dep.("citadel", "core/execution_governance_contract", "~> 0.1.0"),
    citadel_governance: dep.("citadel", "core/citadel_governance", "~> 0.1.0"),
    citadel_host_ingress_bridge: dep.("citadel", "bridges/host_ingress_bridge", "~> 0.1.0"),
    citadel_kernel: dep.("citadel", "core/citadel_kernel", "~> 0.1.0"),
    citadel_observability_contract: dep.("citadel", "core/observability_contract", "~> 0.1.0"),
    citadel_policy_packs: dep.("citadel", "core/policy_packs", "~> 0.1.0"),
    citadel_query_bridge: dep.("citadel", "bridges/query_bridge", "~> 0.1.0"),
    chassis_stack: dep.("chassis", "core/chassis_stack", "~> 0.1.0"),
    execution_plane: %{
      path: Path.join(siblings_root, "execution_plane/core/execution_plane"),
      github: %{
        repo: "nshkrdotcom/execution_plane",
        branch: "main",
        subdir: "core/execution_plane"
      },
      hex: "~> 0.2.0",
      opts: [override: true],
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    ground_plane_persistence_policy: dep.("ground_plane", "core/persistence_policy", "~> 0.1.0"),
    jido_integration_contracts: dep.("jido_integration", "core/contracts", "~> 0.1.0"),
    jido_integration_v2: dep.("jido_integration", "core/platform", "~> 0.1.0"),
    mezzanine_archival_engine: dep.("mezzanine", "core/archival_engine", "~> 0.1.0"),
    mezzanine_audit_engine: dep.("mezzanine", "core/audit_engine", "~> 0.1.0"),
    mezzanine_config_registry: dep.("mezzanine", "core/config_registry", "~> 0.1.0"),
    mezzanine_core: dep.("mezzanine", "core/mezzanine_core", "~> 0.1.0"),
    mezzanine_decision_engine: dep.("mezzanine", "core/decision_engine", "~> 0.1.0"),
    mezzanine_evidence_engine: dep.("mezzanine", "core/evidence_engine", "~> 0.1.0"),
    mezzanine_execution_engine: dep.("mezzanine", "core/execution_engine", "~> 0.1.0"),
    mezzanine_integration_bridge: dep.("mezzanine", "bridges/integration_bridge", "~> 0.1.0"),
    mezzanine_leasing: dep.("mezzanine", "core/leasing", "~> 0.1.0"),
    mezzanine_m1_m2_runtime: dep.("mezzanine", "core/m1_m2_runtime", "~> 0.1.0"),
    mezzanine_object_engine: dep.("mezzanine", "core/object_engine", "~> 0.1.0"),
    mezzanine_operator_engine: dep.("mezzanine", "core/operator_engine", "~> 0.1.0"),
    mezzanine_ops_domain: dep.("mezzanine", "core/ops_domain", "~> 0.1.0"),
    mezzanine_pack_compiler: dep.("mezzanine", "core/pack_compiler", "~> 0.1.0"),
    mezzanine_pack_model: dep.("mezzanine", "core/pack_model", "~> 0.1.0"),
    mezzanine_projection_engine: dep.("mezzanine", "core/projection_engine", "~> 0.1.0"),
    mezzanine_source_engine: dep.("mezzanine", "core/source_engine", "~> 0.1.0"),
    outer_brain_contracts: dep.("outer_brain", "core/outer_brain_contracts", "~> 0.1.0"),
    outer_brain_core: dep.("outer_brain", "core/outer_brain_core", "~> 0.1.0"),
    outer_brain_domain_bridge: dep.("outer_brain", "bridges/domain_bridge", "~> 0.1.0"),
    outer_brain_guardrail_contracts: dep.("outer_brain", "core/guardrail_contracts", "~> 0.1.0"),
    outer_brain_journal: dep.("outer_brain", "core/outer_brain_journal", "~> 0.1.0"),
    outer_brain_memory_contracts: dep.("outer_brain", "core/memory_contracts", "~> 0.1.0"),
    outer_brain_prompt_fabric: dep.("outer_brain", "core/prompt_fabric", "~> 0.1.0"),
    outer_brain_prompting: dep.("outer_brain", "core/outer_brain_prompting", "~> 0.1.0")
  }
}
