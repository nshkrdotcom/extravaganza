if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule Extravaganza.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/extravaganza"
  @workspace_dependencies [
    {:ai_trace_replay_contracts, "~> 0.1.0", override: true},
    {:app_kit_app_config, "~> 0.1.0", override: true},
    {:app_kit_budget_surface, "~> 0.1.0", override: true},
    {:app_kit_chassis_bridge, "~> 0.1.0", override: true},
    {:app_kit_context_surface, "~> 0.1.0", override: true},
    {:app_kit_core, "~> 0.1.0", override: true},
    {:app_kit_cost_dashboard, "~> 0.1.0", override: true},
    {:app_kit_cost_surface, "~> 0.1.0", override: true},
    {:app_kit_eval_studio, "~> 0.1.0", override: true},
    {:app_kit_eval_surface, "~> 0.1.0", override: true},
    {:app_kit_guardrail_surface, "~> 0.1.0", override: true},
    {:app_kit_installation_surface, "~> 0.1.0", override: true},
    {:app_kit_integration_bridge, "~> 0.1.0", override: true},
    {:app_kit_memory_surface, "~> 0.1.0", override: true},
    {:app_kit_mezzanine_bridge, "~> 0.1.0", override: true},
    {:app_kit_operator_console, "~> 0.1.0", override: true},
    {:app_kit_operator_surface, "~> 0.1.0", override: true},
    {:app_kit_policy_authoring, "~> 0.1.0", override: true},
    {:app_kit_projection_bridge, "~> 0.1.0", override: true},
    {:app_kit_prompt_surface, "~> 0.1.0", override: true},
    {:app_kit_replay_surface, "~> 0.1.0", override: true},
    {:app_kit_replay_viewer, "~> 0.1.0", override: true},
    {:app_kit_review_surface, "~> 0.1.0", override: true},
    {:app_kit_run_governance, "~> 0.1.0", override: true},
    {:app_kit_runtime_gateway, "~> 0.1.0", override: true},
    {:app_kit_scope_objects, "~> 0.1.0", override: true},
    {:app_kit_web_components, "~> 0.1.0", override: true},
    {:app_kit_work_control, "~> 0.1.0", override: true},
    {:app_kit_work_surface, "~> 0.1.0", override: true},
    {:chassis_stack, "~> 0.1.0", override: true},
    {:citadel_authority_contract, "~> 0.1.0", override: true},
    {:citadel_contract_core, "~> 0.1.0", override: true},
    {:citadel_domain_surface, "~> 0.1.0", override: true},
    {:citadel_execution_governance_contract, "~> 0.1.0", override: true},
    {:citadel_governance, "~> 0.1.0", override: true},
    {:citadel_host_ingress_bridge, "~> 0.1.0", override: true},
    {:citadel_kernel, "~> 0.1.0", override: true},
    {:citadel_observability_contract, "~> 0.1.0", override: true},
    {:citadel_policy_packs, "~> 0.1.0", override: true},
    {:citadel_query_bridge, "~> 0.1.0", override: true},
    {:execution_plane, "~> 0.2.0", override: true},
    {:ground_plane_persistence_policy, "~> 0.1.0", override: true},
    {:jido_integration_contracts, "~> 0.1.0", override: true},
    {:jido_integration_v2, "~> 0.1.0", override: true},
    {:mezzanine_archival_engine, "~> 0.1.0", override: true},
    {:mezzanine_audit_engine, "~> 0.1.0", override: true},
    {:mezzanine_config_registry, "~> 0.1.0", override: true},
    {:mezzanine_core, "~> 0.1.0", override: true},
    {:mezzanine_decision_engine, "~> 0.1.0", override: true},
    {:mezzanine_evidence_engine, "~> 0.1.0", override: true},
    {:mezzanine_execution_engine, "~> 0.1.0", override: true},
    {:mezzanine_integration_bridge, "~> 0.1.0", override: true},
    {:mezzanine_leasing, "~> 0.1.0", override: true},
    {:mezzanine_m1_m2_runtime, "~> 0.1.0", override: true},
    {:mezzanine_object_engine, "~> 0.1.0", override: true},
    {:mezzanine_operator_engine, "~> 0.1.0", override: true},
    {:mezzanine_ops_domain, "~> 0.1.0", override: true},
    {:mezzanine_pack_compiler, "~> 0.1.0", override: true},
    {:mezzanine_pack_model, "~> 0.1.0", override: true},
    {:mezzanine_projection_engine, "~> 0.1.0", override: true},
    {:mezzanine_source_engine, "~> 0.1.0", override: true},
    {:outer_brain_contracts, "~> 0.1.0", override: true},
    {:outer_brain_core, "~> 0.1.0", override: true},
    {:outer_brain_domain_bridge, "~> 0.1.0", override: true},
    {:outer_brain_guardrail_contracts, "~> 0.1.0", override: true},
    {:outer_brain_journal, "~> 0.1.0", override: true},
    {:outer_brain_memory_contracts, "~> 0.1.0", override: true},
    {:outer_brain_prompt_fabric, "~> 0.1.0", override: true},
    {:outer_brain_prompting, "~> 0.1.0", override: true}
  ]

  def project do
    [
      apps_path: "apps",
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "Extravaganza",
      description: "Umbrella repo for the Extravaganza proving-ground product"
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        test: :test
      ]
    ]
  end

  defp deps do
    tooling_deps = [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: [:dev, :test], runtime: false}
    ]

    tooling_deps ++ Enum.map(@workspace_dependencies, &workspace_dep/1)
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end

  defp aliases do
    [
      "extravaganza.headless.live.linear_source": [
        "run --no-start scripts/headless/live_linear_source.exs --"
      ],
      "extravaganza.headless.live.linear_current_states": [
        "run --no-start scripts/headless/live_linear_current_states.exs --"
      ],
      "extravaganza.headless.live.codex_turn": [
        "run --no-start scripts/headless/live_codex_turn.exs --"
      ],
      "extravaganza.headless.live.linear_publication": [
        "run --no-start scripts/headless/live_linear_publication.exs --"
      ],
      "extravaganza.headless.live.github_evidence": [
        "run --no-start scripts/headless/live_github_evidence.exs --"
      ],
      "extravaganza.headless.live.github_pr_cleanup": [
        "run --no-start scripts/headless/live_github_pr_cleanup.exs --"
      ],
      "extravaganza.headless.live.smoke": ["run --no-start scripts/headless/live_smoke.exs --"],
      test: ["cmd --cd #{core_app_path()} env MIX_ENV=test mix ash.setup --quiet", "test"],
      ci: [
        "deps.get",
        no_bypass_gate(),
        "format --check-formatted",
        "compile --warnings-as-errors",
        "extravaganza.headless.specs.check",
        "cmd env MIX_ENV=test mix test",
        "credo --strict",
        "dialyzer --force-check",
        "docs --warnings-as-errors"
      ]
    ]
  end

  defp core_app_path do
    Path.expand("apps/extravaganza_core", __DIR__)
  end

  defp app_kit_path do
    Path.expand("../app_kit", __DIR__)
  end

  defp no_bypass_gate do
    "cmd --cd #{app_kit_path()} mix app_kit.no_bypass.scan --root #{__DIR__} " <>
      "--profile product --profile hazmat " <>
      "--include apps/extravaganza_core/lib/**/*.ex " <>
      "--include apps/extravaganza_web/lib/**/*.ex"
  end

  defp dialyzer do
    [
      plt_add_deps: :apps_tree,
      plt_add_apps: [:mix, :ex_unit]
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "Extravaganza",
      logo: "assets/extravaganza.svg",
      assets: %{"assets" => "assets"},
      source_ref: "main",
      source_url: @source_url,
      homepage_url: @source_url,
      extras: [
        "README.md",
        "guides/headless_api_reference.md",
        "guides/headless_live_demo.md",
        "guides/headless_provider_credentials.md",
        "guides/headless_full_functionality_verification.md",
        "guides/code_smell_remediation.md",
        "guides/headless_symphony_parity_map.md",
        "guides/headless_symphony_workflow_profiles.md",
        "docs/overview.md",
        "docs/stack_position.md",
        "docs/product_direction.md",
        "docs/product_profile.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Overview: ["README.md", "docs/overview.md"],
        Guides: [
          "guides/headless_api_reference.md",
          "guides/headless_live_demo.md",
          "guides/headless_provider_credentials.md",
          "guides/headless_full_functionality_verification.md",
          "guides/code_smell_remediation.md",
          "guides/headless_symphony_parity_map.md",
          "guides/headless_symphony_workflow_profiles.md"
        ],
        Architecture: ["docs/stack_position.md", "docs/product_direction.md"],
        Composition: ["docs/product_profile.md"],
        Project: ["CHANGELOG.md", "LICENSE"]
      ]
    ]
  end
end
