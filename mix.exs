defmodule Extravaganza.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/extravaganza"

  def project do
    [
      app: :extravaganza,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "Extravaganza",
      description:
        "Thin proving-ground product app above AppKit and Mezzanine for distributed AI operations"
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
    [
      {:ex_doc, "~> 0.40.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "deps.get",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "docs"
      ]
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
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Overview: ["README.md", "docs/overview.md"],
        Architecture: ["docs/stack_position.md", "docs/product_direction.md"],
        Project: ["CHANGELOG.md", "LICENSE"]
      ]
    ]
  end
end
