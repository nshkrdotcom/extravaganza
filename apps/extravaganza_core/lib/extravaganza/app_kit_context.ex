defmodule Extravaganza.AppKitContext do
  @moduledoc """
  Product-owned request-context helpers for northbound AppKit calls.
  """

  alias AppKit.Core.{InstallationRef, RequestContext}
  alias Extravaganza.{Config, ProductProfile}

  @actor_ref %{id: "extravaganza_core", kind: :system, roles: ["product_core"]}

  @spec bootstrap_context(Config.t(), keyword()) :: RequestContext.t()
  def bootstrap_context(%Config{} = config, opts \\ []),
    do: context(config, nil, bootstrap_metadata(config, opts), opts)

  @spec product_context(Config.t(), InstallationRef.t(), keyword()) :: RequestContext.t()
  def product_context(%Config{} = config, %InstallationRef{} = installation_ref, opts \\ []),
    do: context(config, installation_ref, product_metadata(config, installation_ref, opts), opts)

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

  defp bootstrap_metadata(%Config{} = config, opts) do
    routing_metadata(config)
    |> Map.put(:runtime_profile, ProductProfile.profile(config))
    |> put_product_boundary_metadata(opts)
  end

  defp product_metadata(%Config{} = config, %InstallationRef{} = installation_ref, opts) do
    config
    |> routing_metadata()
    |> Map.put(:installation_revision, installation_ref.compiled_pack_revision || 1)
    |> Map.put(:activation_epoch, 1)
    |> Map.put(:lease_epoch, 1)
    |> put_product_boundary_metadata(opts)
  end

  defp context(%Config{} = config, installation_ref, metadata, opts) do
    case RequestContext.new(%{
           trace_id: Keyword.get(opts, :trace_id),
           actor_ref: @actor_ref,
           tenant_ref: %{id: config.tenant_id},
           installation_ref: installation_ref,
           causation_id: Keyword.get(opts, :correlation_id) || Keyword.get(opts, :causation_id),
           request_id: Keyword.get(opts, :request_id),
           idempotency_key: Keyword.get(opts, :idempotency_key),
           metadata: metadata
         }) do
      {:ok, context} -> context
      {:error, reason} -> raise ArgumentError, "invalid app kit context: #{inspect(reason)}"
    end
  end

  defp put_product_boundary_metadata(metadata, opts) do
    boundary =
      opts
      |> Keyword.take([
        :installation_id,
        :program_id,
        :profile_ref,
        :source_binding_ref,
        :credential_ref,
        :credential_lease_ref,
        :live?
      ])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    if boundary == %{} do
      metadata
    else
      Map.put(metadata, :product_boundary_options, boundary)
    end
  end
end
