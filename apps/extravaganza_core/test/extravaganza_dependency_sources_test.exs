defmodule Extravaganza.DependencySourcesTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../../..", __DIR__)
  @dependency_sources Path.join(@repo_root, "build_support/dependency_sources.exs")
  @config_path Path.join(@repo_root, "build_support/dependency_sources.config.exs")
  @expected_apps [
    :ai_trace_replay_contracts,
    :app_kit_app_config,
    :app_kit_budget_surface,
    :app_kit_context_surface,
    :app_kit_cost_dashboard,
    :app_kit_cost_surface,
    :app_kit_core,
    :app_kit_eval_studio,
    :app_kit_eval_surface,
    :app_kit_guardrail_surface,
    :app_kit_installation_surface,
    :app_kit_integration_bridge,
    :app_kit_memory_surface,
    :app_kit_mezzanine_bridge,
    :app_kit_operator_console,
    :app_kit_operator_surface,
    :app_kit_policy_authoring,
    :app_kit_projection_bridge,
    :app_kit_prompt_surface,
    :app_kit_replay_surface,
    :app_kit_replay_viewer,
    :app_kit_review_surface,
    :app_kit_run_governance,
    :app_kit_runtime_gateway,
    :app_kit_scope_objects,
    :app_kit_web_components,
    :app_kit_work_control,
    :app_kit_work_surface,
    :citadel_authority_contract,
    :citadel_contract_core,
    :citadel_domain_surface,
    :citadel_execution_governance_contract,
    :citadel_governance,
    :citadel_host_ingress_bridge,
    :citadel_kernel,
    :citadel_observability_contract,
    :citadel_policy_packs,
    :citadel_query_bridge,
    :execution_plane,
    :ground_plane_persistence_policy,
    :jido_integration_contracts,
    :jido_integration_v2,
    :mezzanine_archival_engine,
    :mezzanine_audit_engine,
    :mezzanine_config_registry,
    :mezzanine_core,
    :mezzanine_decision_engine,
    :mezzanine_evidence_engine,
    :mezzanine_execution_engine,
    :mezzanine_integration_bridge,
    :mezzanine_leasing,
    :mezzanine_m1_m2_runtime,
    :mezzanine_object_engine,
    :mezzanine_operator_engine,
    :mezzanine_ops_domain,
    :mezzanine_pack_compiler,
    :mezzanine_pack_model,
    :mezzanine_projection_engine,
    :mezzanine_source_engine,
    :outer_brain_contracts,
    :outer_brain_core,
    :outer_brain_domain_bridge,
    :outer_brain_guardrail_contracts,
    :outer_brain_journal,
    :outer_brain_memory_contracts,
    :outer_brain_prompt_fabric,
    :outer_brain_prompting
  ]

  test "declares every cross-repo dependency in the no-env dependency manifest" do
    config = DependencySources.config!(@repo_root)
    deps = Map.fetch!(config, :deps)

    assert Enum.sort(Map.keys(deps)) == Enum.sort(@expected_apps)

    Enum.each(deps, fn {app, dep_config} ->
      assert dep_config.path, "#{app} must keep a local path candidate"
      assert dep_config.github.repo, "#{app} must keep a GitHub fallback"
      assert dep_config.github.branch == "main"
      assert dep_config.github.subdir
      assert dep_config.hex, "#{app} must keep a Hex publish-mode requirement"
      assert dep_config.opts == [override: true]
      assert dep_config.default_order in [[:path, :github, :hex], [:github, :hex, :path]]
      assert dep_config.publish_order == [:hex]
    end)

    dependency_source = File.read!(@dependency_sources)
    config_source = File.read!(@config_path)

    refute String.contains?(dependency_source, "Code.eval_file")
    refute String.contains?(dependency_source, "String.to_atom")
    refute String.contains?(dependency_source, "String.to_existing_atom")
    refute String.contains?(config_source, "System.get_env")
  end

  test "umbrella root owns clean-clone dependency overrides" do
    dep_options_by_app =
      DependencySources.deps(@repo_root)
      |> Map.new(fn
        {app, opts} when is_list(opts) -> {app, opts}
        {app, _requirement, opts} -> {app, opts}
        {app, _requirement} -> {app, []}
      end)

    Enum.each(@expected_apps, fn app ->
      assert Keyword.get(Map.fetch!(dep_options_by_app, app), :override) == true
    end)
  end

  test "nested Mix projects use the dependency-source helper instead of raw sibling paths" do
    mix_files = [
      Path.join(@repo_root, "mix.exs"),
      Path.join(@repo_root, "apps/extravaganza_core/mix.exs"),
      Path.join(@repo_root, "apps/extravaganza_web/mix.exs")
    ]

    contents = Enum.map(mix_files, &File.read!/1)

    assert Enum.any?(contents, &String.contains?(&1, "DependencySources.deps(@repo_root)"))
    assert Enum.any?(contents, &String.contains?(&1, "DependencySources.dep(&1"))
    assert Enum.any?(contents, &String.contains?(&1, ":app_kit_core"))

    assert Enum.any?(
             contents,
             &String.contains?(&1, "DependencySources.dep(:app_kit_operator_console")
           )

    weld_dep_pattern = "{" <> ":weld,"

    Enum.each(contents, fn content ->
      refute String.contains?(content, "../../../app_kit")
      refute String.contains?(content, "../../../mezzanine")
      refute String.contains?(content, weld_dep_pattern)
    end)
  end
end
