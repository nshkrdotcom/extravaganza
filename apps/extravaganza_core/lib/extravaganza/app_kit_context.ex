defmodule Extravaganza.AppKitContext do
  @moduledoc """
  Product-owned request-context helpers for northbound AppKit calls.
  """

  alias AppKit.Core.{InstallationRef, RequestContext, TraceIdentity}
  alias Extravaganza.{Config, ProductProfile}

  @actor_ref %{id: "extravaganza_core", kind: :system, roles: ["product_core"]}

  @spec bootstrap_context(Config.t()) :: RequestContext.t()
  def bootstrap_context(%Config{} = config),
    do: context(config, "bootstrap", nil, bootstrap_metadata(config))

  @spec product_context(Config.t(), InstallationRef.t()) :: RequestContext.t()
  def product_context(%Config{} = config, %InstallationRef{} = installation_ref),
    do: context(config, "product", installation_ref, product_metadata(config, installation_ref))

  @spec routing_metadata(Config.t()) :: map()
  def routing_metadata(%Config{} = config) do
    %{
      program_slug: config.program_slug,
      work_class_name: config.work_class_name,
      product_family: config.product_family
    }
  end

  @spec scope_id(Config.t()) :: String.t()
  def scope_id(%Config{} = config), do: "program/#{config.program_slug}"

  defp bootstrap_metadata(%Config{} = config) do
    routing_metadata(config)
    |> Map.put(:runtime_profile, ProductProfile.profile(config))
  end

  defp product_metadata(%Config{} = config, %InstallationRef{} = installation_ref) do
    config
    |> routing_metadata()
    |> Map.put(:installation_revision, installation_ref.compiled_pack_revision || 1)
    |> Map.put(:activation_epoch, 1)
    |> Map.put(:lease_epoch, 1)
  end

  defp context(%Config{} = config, purpose, installation_ref, metadata) do
    case RequestContext.new(%{
           trace_id: trace_id(purpose),
           actor_ref: @actor_ref,
           tenant_ref: %{id: config.tenant_id},
           installation_ref: installation_ref,
           metadata: metadata
         }) do
      {:ok, context} -> context
      {:error, reason} -> raise ArgumentError, "invalid app kit context: #{inspect(reason)}"
    end
  end

  defp trace_id(_purpose), do: TraceIdentity.mint()
end
