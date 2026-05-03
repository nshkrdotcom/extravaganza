defmodule ExtravaganzaEnvGovernanceTest do
  use ExUnit.Case, async: false

  alias Extravaganza.{
    Config,
    DefaultAuthoringBundle,
    ProductInstallTemplate,
    ProductPack,
    ProductProfile
  }

  @env_samples %{
    "OPENAI_API_KEY" => "env-openai-key-should-not-appear",
    "CODEX_API_KEY" => "env-codex-key-should-not-appear",
    "LINEAR_API_KEY" => "env-linear-key-should-not-appear",
    "GITHUB_TOKEN" => "env-github-token-should-not-appear",
    "BASE_URL" => "https://env-base-url.invalid",
    "EXTRAVAGANZA_TARGET" => "env-target-should-not-appear"
  }

  setup do
    previous =
      Map.new(@env_samples, fn {name, _value} ->
        {name, System.get_env(name)}
      end)

    Enum.each(@env_samples, fn {name, value} ->
      System.put_env(name, value)
    end)

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  test "product config and pack authority ignore provider env secrets and targets" do
    config = Config.load()
    profile = ProductProfile.profile(config)
    install_template = ProductInstallTemplate.default(config)

    assert config.linear_source_kind == "linear"
    assert ProductPack.source_binding_key(config) == "linear_primary"
    assert ProductPack.placement_key(config) == "local_default"
    assert ProductPack.profile_slots(config).runtime_profile_ref == :codex_session

    assert get_in(install_template.default_bindings, [
             "source_bindings",
             "linear_primary",
             "provider"
           ]) == "linear"

    assert get_in(install_template.default_bindings, [
             "source_bindings",
             "linear_primary",
             "connection_ref"
           ]) == "linear_primary"

    refute_contains_env_sample!(config)
    refute_contains_env_sample!(profile)
    refute_contains_env_sample!(install_template.default_bindings)
    refute_contains_env_sample!(ProductPack.manifest(config))
  end

  test "authoring bundle and product profile do not project raw env secret values" do
    config = Config.load()

    assert {:ok, bundle} =
             DefaultAuthoringBundle.build(config, installation_id: "env-governance-test")

    refute_contains_env_sample!(bundle)
    refute_contains_env_sample!(ProductProfile.profile(config))
  end

  defp refute_contains_env_sample!(value) do
    encoded = inspect(value, limit: :infinity, printable_limit: :infinity)

    Enum.each(@env_samples, fn {_name, sample} ->
      refute String.contains?(encoded, sample)
    end)
  end
end
