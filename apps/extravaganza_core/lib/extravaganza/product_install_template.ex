defmodule Extravaganza.ProductInstallTemplate do
  @moduledoc """
  Product-owned default installation template for the Extravaganza runtime.
  """

  alias AppKit.Core.InstallTemplate
  alias Extravaganza.{Config, ProductPack}
  alias Extravaganza.RunProfiles.DefaultCodexProfile

  @companion_contract_version "connector-sdk.v1"
  @linear_companion_manifest_hash "sha256:1a0f1e6d8e0d9c4b3a2f105f91c8d7e6a5b4c3d2e1f011223344556677889900"

  @spec default(Config.t()) :: InstallTemplate.t()
  def default(%Config{} = config) do
    case InstallTemplate.new(%{
           template_key: template_key(config),
           pack_slug: ProductPack.pack_slug(config),
           pack_version: ProductPack.pack_version(config),
           default_bindings: default_bindings(config),
           metadata: metadata(config)
         }) do
      {:ok, template} -> template
      {:error, reason} -> raise ArgumentError, "invalid install template: #{inspect(reason)}"
    end
  end

  @spec template_key(Config.t()) :: String.t()
  def template_key(%Config{} = config), do: "#{config.program_slug}:default"

  @spec companion_connectors(Config.t()) :: [map()]
  def companion_connectors(%Config{} = config) do
    [
      %{
        "connector_ref" => companion_connector_ref(config),
        "module" => "Extravaganza.Companions.LinearSafeRead.Connector",
        "package" => "extravaganza_linear_safe_read_companion",
        "tenant_ref" => tenant_ref(config),
        "app_config_ref" => "app-config://#{config.tenant_id}/linear-safe-read-companion",
        "manifest_hash" => @linear_companion_manifest_hash,
        "contract_version" => @companion_contract_version,
        "conformance_ref" => "conformance://#{config.tenant_id}/linear-safe-read-companion",
        "capability_ids" => ["extravaganza_linear_safe_read.issue.fetch"],
        "auth_profiles" => ["default_manual_secret"],
        "scopes" => ["linear:read"],
        "persistence_profile" => "memory-default",
        "admission_policy" => "explicit_app_config_only"
      }
    ]
  end

  defp default_bindings(%Config{} = config) do
    %{
      "execution_bindings" => %{
        ProductPack.execution_binding_key(config) => %{
          "runtime_profile_ref" => DefaultCodexProfile.profile_ref(),
          "placement_ref" => ProductPack.placement_key(config),
          "authority_decision_ref" =>
            "authority-decision://#{ProductPack.pack_slug(config)}/default",
          "connector_binding_ref" =>
            "connector-binding://#{ProductPack.source_binding_key(config)}",
          "no_credentials_posture_ref" =>
            "no-credentials://#{ProductPack.pack_slug(config)}/default",
          "execution_params" => %{"timeout_ms" => config.execution_timeout_ms}
        }
      },
      "source_bindings" => %{
        ProductPack.source_binding_key(config) => %{
          "provider" => "linear",
          "connection_ref" => "linear_primary",
          "source_kind" => config.linear_source_kind
        }
      }
    }
  end

  defp metadata(%Config{} = config) do
    %{
      "managed_by" => "extravaganza_core",
      "product_family" => config.product_family,
      "profile" => "default",
      "companion_connectors" => companion_connectors(config)
    }
  end

  defp companion_connector_ref(%Config{} = config) do
    "connector://#{config.tenant_id}/extravaganza-linear-safe-read"
  end

  defp tenant_ref(%Config{} = config), do: "tenant://#{config.tenant_id}"
end
