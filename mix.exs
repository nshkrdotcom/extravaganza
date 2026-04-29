defmodule Extravaganza.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/extravaganza"

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
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      test: ["cmd --cd #{core_app_path()} env MIX_ENV=test mix ash.setup --quiet", "test"],
      ci: [
        "deps.get",
        no_bypass_gate(),
        "format --check-formatted",
        "compile --warnings-as-errors",
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
        "docs/overview.md",
        "docs/stack_position.md",
        "docs/product_direction.md",
        "docs/product_profile.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Overview: ["README.md", "docs/overview.md"],
        Architecture: ["docs/stack_position.md", "docs/product_direction.md"],
        Composition: ["docs/product_profile.md"],
        Project: ["CHANGELOG.md", "LICENSE"]
      ]
    ]
  end
end
