unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule ExtravaganzaWeb.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/extravaganza"
  @repo_root Path.expand("../..", __DIR__)

  def project do
    [
      app: :extravaganza_web,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "Extravaganza Web",
      description: "Phoenix web shell app for the Extravaganza umbrella"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {ExtravaganzaWeb.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:extravaganza_core, in_umbrella: true},
      DependencySources.dep(:app_kit_operator_console, @repo_root, override: true),
      {:phoenix, "~> 1.8.1"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.1.0"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"}
    ]
  end
end
