defmodule ExtravaganzaWeb.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/extravaganza"

  def project do
    [
      app: :extravaganza_web,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "Extravaganza Web",
      description: "Placeholder web-shell app for the Extravaganza umbrella"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:extravaganza_core, in_umbrella: true}
    ]
  end
end
