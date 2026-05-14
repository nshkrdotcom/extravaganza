defmodule Extravaganza.ProductSurface do
  @moduledoc false

  alias AppKit.Core.RequestContext
  alias Extravaganza.{AppKitContext, Config, ProductBootstrap}

  @config_override_keys [
    :tenant_id,
    :program_slug,
    :program_name,
    :product_family,
    :pack_version,
    :policy_bundle_name,
    :policy_bundle_version,
    :work_class_name,
    :work_class_kind,
    :placement_profile_id,
    :execution_timeout_ms,
    :linear_source_kind,
    :operator_surface_enabled?
  ]

  @normalized_option_aliases %{
    tenant_id: [:tenant_id, "tenant_id"],
    pack_version: [:pack_version, "pack_version"],
    installation_id: [:installation_id, "installation_id", :installation_ref, "installation_ref"],
    program_id: [:program_id, "program_id", :program_slug, "program_slug"],
    profile_ref: [:profile_ref, "profile_ref", :runtime_profile_ref, "runtime_profile_ref"],
    source_binding_ref: [
      :source_binding_ref,
      "source_binding_ref",
      :source_binding_id,
      "source_binding_id",
      :source_binding_key,
      "source_binding_key"
    ],
    credential_ref: [:credential_ref, "credential_ref"],
    credential_lease_ref: [:credential_lease_ref, "credential_lease_ref"],
    live?: [
      :live?,
      "live?",
      :live,
      "live",
      :live_product_path?,
      "live_product_path?",
      :live_product_path,
      "live_product_path"
    ],
    trace_id: [:trace_id, "trace_id"],
    correlation_id: [:correlation_id, "correlation_id", :causation_id, "causation_id"]
  }

  @normalized_option_alias_keys @normalized_option_aliases
                                |> Map.values()
                                |> List.flatten()
                                |> MapSet.new()

  @spec bootstrapped_context(keyword()) ::
          {:ok, %{config: Config.t(), context: RequestContext.t(), profile: map()}}
          | {:error, term()}
  def bootstrapped_context(opts) when is_list(opts) or is_map(opts) do
    config = opts |> config_overrides() |> Config.load()
    product_opts = normalized_options(config, opts)

    with {:ok, profile} <- ProductBootstrap.ensure_bootstrapped(product_opts) do
      {:ok,
       %{
         config: profile.config,
         context:
           AppKitContext.product_context(profile.config, profile.installation_ref, product_opts),
         profile: profile
       }}
    end
  end

  @spec normalized_options(Config.t(), keyword() | map()) :: keyword()
  def normalized_options(%Config{} = config, opts) when is_list(opts) or is_map(opts) do
    attrs = option_map(opts)

    attrs
    |> passthrough_opts()
    |> Keyword.merge(
      compact_opts(
        tenant_id: option_value(attrs, :tenant_id) || config.tenant_id,
        pack_version: option_value(attrs, :pack_version) || config.pack_version,
        installation_id: option_value(attrs, :installation_id),
        program_id: option_value(attrs, :program_id),
        profile_ref: option_value(attrs, :profile_ref),
        source_binding_ref: option_value(attrs, :source_binding_ref),
        credential_ref: option_value(attrs, :credential_ref),
        credential_lease_ref: option_value(attrs, :credential_lease_ref),
        live?: live_option(attrs),
        trace_id: option_value(attrs, :trace_id),
        correlation_id: option_value(attrs, :correlation_id)
      )
    )
  end

  @spec work_control_opts(Config.t(), keyword()) :: keyword()
  def work_control_opts(%Config{} = config, opts) when is_list(opts) or is_map(opts) do
    scoped_opts(config, opts)
  end

  @spec work_query_opts(Config.t(), keyword()) :: keyword()
  def work_query_opts(%Config{} = config, opts) when is_list(opts) or is_map(opts) do
    scoped_opts(config, opts)
  end

  @spec operator_opts(Config.t(), keyword()) :: keyword()
  def operator_opts(%Config{} = config, opts) when is_list(opts) or is_map(opts) do
    config
    |> normalized_options(opts)
    |> Keyword.put(:tenant_id, config.tenant_id)
    |> Keyword.put(:config, %{operator_surface?: config.operator_surface_enabled?})
  end

  defp scoped_opts(%Config{} = config, opts) when is_list(opts) or is_map(opts) do
    config
    |> normalized_options(opts)
    |> Keyword.put(:scope_id, AppKitContext.scope_id(config))
  end

  defp config_overrides(opts) do
    attrs = option_map(opts)

    @config_override_keys
    |> Enum.reduce([], fn key, acc ->
      value = first_present(attrs, [key, Atom.to_string(key)])

      if is_nil(value), do: acc, else: Keyword.put(acc, key, value)
    end)
  end

  defp option_map(opts) when is_list(opts), do: Map.new(opts)
  defp option_map(opts) when is_map(opts), do: opts

  defp passthrough_opts(attrs) do
    attrs
    |> Enum.reduce([], fn
      {key, value}, acc when is_atom(key) ->
        if MapSet.member?(@normalized_option_alias_keys, key) do
          acc
        else
          Keyword.put(acc, key, value)
        end

      {_key, _value}, acc ->
        acc
    end)
  end

  defp option_value(attrs, key),
    do: first_present(attrs, Map.fetch!(@normalized_option_aliases, key))

  defp first_present(attrs, keys) do
    keys
    |> Enum.find_value(fn key ->
      case Map.get(attrs, key) do
        nil -> nil
        "" -> nil
        value -> value
      end
    end)
  end

  defp live_option(attrs) do
    attrs
    |> option_value(:live?)
    |> truthy?()
  end

  defp truthy?(value) when value in [true, 1], do: true
  defp truthy?(value) when is_binary(value), do: value in ["true", "1", "yes", "on"]
  defp truthy?(_value), do: false

  defp compact_opts(opts) do
    Enum.reject(opts, fn {_key, value} -> is_nil(value) end)
  end
end
