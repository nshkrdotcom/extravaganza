defmodule Extravaganza.DependencySourcesTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../../..", __DIR__)
  @config_path Path.join(@repo_root, "build_support/dependency_sources.config.exs")
  @expected_apps [
    :app_kit_core,
    :app_kit_installation_surface,
    :app_kit_operator_console,
    :app_kit_operator_surface,
    :app_kit_prompt_surface,
    :app_kit_review_surface,
    :app_kit_work_control,
    :app_kit_work_surface,
    :mezzanine_pack_model
  ]

  test "declares every cross-repo dependency in the no-env dependency manifest" do
    {config, _binding} = Code.eval_file(@config_path)

    deps = Map.fetch!(config, :deps)

    assert Enum.sort(Map.keys(deps)) == @expected_apps

    Enum.each(deps, fn {app, dep_config} ->
      assert dep_config.path, "#{app} must keep a local path candidate"
      assert dep_config.github.repo, "#{app} must keep a GitHub fallback"
      assert dep_config.github.branch == "main"
      assert dep_config.github.subdir
      assert dep_config.hex, "#{app} must keep a Hex publish-mode requirement"
      assert dep_config.default_order == [:path, :github, :hex]
      assert dep_config.publish_order == [:hex]
    end)
  end

  test "nested Mix projects use the dependency-source helper instead of raw sibling paths" do
    mix_files = [
      Path.join(@repo_root, "apps/extravaganza_core/mix.exs"),
      Path.join(@repo_root, "apps/extravaganza_web/mix.exs")
    ]

    contents = Enum.map(mix_files, &File.read!/1)

    assert Enum.any?(contents, &String.contains?(&1, "DependencySources.dep(:app_kit_core"))

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
