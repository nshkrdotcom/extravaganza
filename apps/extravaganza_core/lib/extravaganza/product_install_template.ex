defmodule Extravaganza.ProductInstallTemplate do
  @moduledoc """
  Product-owned default installation template for the Extravaganza runtime.
  """

  alias AppKit.Core.InstallTemplate
  alias Extravaganza.{Config, ProductPack}

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

  defp default_bindings(%Config{} = config) do
    %{
      "execution_bindings" => %{
        ProductPack.execution_binding_key(config) => %{
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
      "profile" => "default"
    }
  end
end
