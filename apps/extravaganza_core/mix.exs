if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule ExtravaganzaCore.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/extravaganza"
  @runtime_dependencies [
    {:app_kit_core, "~> 0.1.0", override: true},
    {:app_kit_chassis_bridge, "~> 0.1.0", override: true},
    {:app_kit_context_surface, "~> 0.1.0", override: true},
    {:mezzanine_pack_model, "~> 0.1.0", override: true},
    {:app_kit_installation_surface, "~> 0.1.0", override: true},
    {:app_kit_prompt_surface, "~> 0.1.0", override: true},
    {:app_kit_runtime_gateway, "~> 0.1.0", override: true},
    {:app_kit_work_surface, "~> 0.1.0", override: true},
    {:app_kit_mezzanine_bridge, "~> 0.1.0", override: true},
    {:app_kit_work_control, "~> 0.1.0", override: true},
    {:app_kit_review_surface, "~> 0.1.0", override: true},
    {:app_kit_operator_surface, "~> 0.1.0", override: true},
    {:chassis_stack, "~> 0.1.0", override: true}
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
      Enum.map(@runtime_dependencies, &workspace_dep/1)
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp aliases do
    [
      test: ["ash.setup --quiet", "test"]
    ]
  end
end
