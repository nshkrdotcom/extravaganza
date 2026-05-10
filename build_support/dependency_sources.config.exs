repo_root = Path.expand("..", __DIR__)
siblings_root = Path.expand("..", repo_root)

dep = fn repo, subdir, hex ->
  %{
    path: Path.join(siblings_root, "#{repo}/#{subdir}"),
    github: %{repo: "nshkrdotcom/#{repo}", branch: "main", subdir: subdir},
    hex: hex,
    default_order: [:path, :github, :hex],
    publish_order: [:hex]
  }
end

%{
  deps: %{
    app_kit_core: dep.("app_kit", "core/app_kit_core", "~> 0.1.0"),
    app_kit_installation_surface: dep.("app_kit", "core/installation_surface", "~> 0.1.0"),
    app_kit_operator_console: dep.("app_kit", "web/operator_console", "~> 0.1.0"),
    app_kit_operator_surface: dep.("app_kit", "core/operator_surface", "~> 0.1.0"),
    app_kit_prompt_surface: dep.("app_kit", "core/prompt_surface", "~> 0.1.0"),
    app_kit_review_surface: dep.("app_kit", "core/review_surface", "~> 0.1.0"),
    app_kit_work_control: dep.("app_kit", "core/work_control", "~> 0.1.0"),
    app_kit_work_surface: dep.("app_kit", "core/work_surface", "~> 0.1.0"),
    mezzanine_pack_model: dep.("mezzanine", "core/pack_model", "~> 0.1.0")
  }
}
