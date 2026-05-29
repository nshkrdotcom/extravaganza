defmodule Extravaganza.ProductBootstrap do
  @moduledoc """
  Idempotent bootstrap of the Extravaganza default product profile through the
  northbound AppKit installation surface.
  """

  alias AppKit.Core.SurfaceError
  alias AppKit.InstallationSurface

  alias Extravaganza.{
    AppKitContext,
    Config,
    DefaultAuthoringBundle,
    ProductInstallTemplate,
    ProductPack
  }

  @spec ensure_bootstrapped(keyword() | map()) ::
          {:ok,
           %{
             config: Extravaganza.Config.t(),
             install_result: AppKit.Core.InstallResult.t(),
             authoring_result: AppKit.Core.InstallResult.t(),
             bootstrap_install_result: AppKit.Core.InstallResult.t() | nil,
             install_template: AppKit.Core.InstallTemplate.t(),
             installation_ref: AppKit.Core.InstallationRef.t(),
             pack: map(),
             routing: map()
           }}
          | {:error, term()}
  def ensure_bootstrapped(overrides \\ []) do
    config = Config.load(overrides)
    context_opts = context_options(overrides)
    install_template = ProductInstallTemplate.default(config)

    with {:ok, bootstrap_install_result} <-
           ensure_installation(config, install_template, context_opts),
         {:ok, bundle_import} <- default_bundle_import(config, bootstrap_install_result),
         {:ok, bundle_result} <-
           import_authoring_bundle(config, bootstrap_install_result, bundle_import, context_opts),
         {:ok, install_result} <-
           ensure_post_import_installation(
             config,
             install_template,
             bootstrap_install_result,
             context_opts
           ) do
      {:ok,
       %{
         config: config,
         install_template: install_template,
         install_result: install_result,
         authoring_result: bundle_result,
         bootstrap_install_result: bootstrap_install_result,
         installation_ref: install_result.installation_ref,
         bundle:
           Map.get(bundle_result.metadata, :bundle) || Map.get(bundle_result.metadata, "bundle"),
         pack: %{
           slug: ProductPack.pack_slug(config),
           version: ProductPack.pack_version(config)
         },
         routing: AppKitContext.routing_metadata(config)
       }}
    end
  end

  @spec cached_installation_ref() :: String.t()
  def cached_installation_ref do
    Application.get_env(:extravaganza_core, :installation_ref, "installation:extravaganza:local")
  end

  defp ensure_installation(%Config{} = config, install_template, context_opts) do
    context = AppKitContext.bootstrap_context(config, context_opts)

    case call_installation_surface(:create_installation, [context, install_template]) do
      {:ok, install_result} ->
        {:ok, install_result}

      {:error, %SurfaceError{code: code}}
      when code in ["pack_registration_not_found", "pack_registration_not_active"] ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp default_bundle_import(%Config{} = config, nil) do
    DefaultAuthoringBundle.build(config,
      installation_id: DefaultAuthoringBundle.default_installation_id()
    )
  end

  defp default_bundle_import(%Config{} = config, install_result) do
    DefaultAuthoringBundle.build(config, installation_ref: install_result.installation_ref)
  end

  defp import_authoring_bundle(%Config{} = config, nil, bundle_import, context_opts) do
    call_installation_surface(:import_authoring_bundle, [
      AppKitContext.bootstrap_context(config, context_opts),
      bundle_import,
      [replace_overlapping_active?: true]
    ])
  end

  defp import_authoring_bundle(%Config{} = config, install_result, bundle_import, context_opts) do
    call_installation_surface(:import_authoring_bundle, [
      AppKitContext.product_context(config, install_result.installation_ref, context_opts),
      bundle_import,
      [replace_overlapping_active?: true]
    ])
  end

  defp ensure_post_import_installation(config, install_template, nil, context_opts) do
    case ensure_installation(config, install_template, context_opts) do
      {:ok, nil} -> {:error, :runtime_installation_not_provisioned}
      result -> result
    end
  end

  defp ensure_post_import_installation(_config, _install_template, install_result, _context_opts),
    do: {:ok, install_result}

  defp context_options(overrides) do
    attrs =
      case overrides do
        opts when is_list(opts) -> Map.new(opts)
        opts when is_map(opts) -> opts
      end

    [
      trace_id: first_present(attrs, [:trace_id, "trace_id"]),
      correlation_id:
        first_present(attrs, [:correlation_id, "correlation_id", :causation_id, "causation_id"]),
      request_id: first_present(attrs, [:request_id, "request_id"]),
      idempotency_key: first_present(attrs, [:idempotency_key, "idempotency_key"]),
      installation_id: first_present(attrs, [:installation_id, "installation_id"]),
      program_id: first_present(attrs, [:program_id, "program_id"]),
      profile_ref:
        first_present(attrs, [
          :profile_ref,
          "profile_ref",
          :runtime_profile_ref,
          "runtime_profile_ref"
        ]),
      source_binding_ref: first_present(attrs, [:source_binding_ref, "source_binding_ref"]),
      credential_ref: first_present(attrs, [:credential_ref, "credential_ref"]),
      credential_lease_ref: first_present(attrs, [:credential_lease_ref, "credential_lease_ref"]),
      live?: truthy?(first_present(attrs, [:live?, "live?", :live, "live"]))
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

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

  defp truthy?(value) when value in [true, 1], do: true
  defp truthy?(value) when is_binary(value), do: value in ["true", "1", "yes", "on"]
  defp truthy?(_value), do: false

  # InstallationSurface dispatches to a runtime-configured backend in product hosts.
  defp call_installation_surface(function, args) do
    apply(InstallationSurface, function, args)
  end
end
