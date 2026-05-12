unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule ExtravaganzaCore.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/extravaganza"
  @repo_root Path.expand("../..", __DIR__)
  @runtime_dependency_apps [
    :app_kit_core,
    :mezzanine_pack_model,
    :app_kit_installation_surface,
    :app_kit_prompt_surface,
    :app_kit_work_surface,
    :app_kit_work_control,
    :app_kit_review_surface,
    :app_kit_operator_surface
  ]

  def project do
    [
      app: :extravaganza_core,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "Extravaganza Core",
      description: "Product-core app for the Extravaganza proving-ground product"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Extravaganza.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test
      ]
    ]
  end

  defp deps do
    [{:jason, "~> 1.4"}, {:solid, "~> 1.2"}] ++
      dependency_sources(@runtime_dependency_apps, override: true)
  end

  defp dependency_sources(apps, opts) do
    Enum.map(apps, &DependencySources.dep(&1, @repo_root, opts))
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp aliases do
    [
      test: ["ash.setup --quiet", "test"]
    ]
  end
end
