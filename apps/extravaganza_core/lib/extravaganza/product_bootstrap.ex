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
    install_template = ProductInstallTemplate.default(config)

    with {:ok, install_result} <- ensure_installation(config, install_template),
         {:ok, bundle_import} <- default_bundle_import(config, install_result),
         {:ok, bundle_result} <- import_authoring_bundle(config, install_result, bundle_import) do
      {:ok,
       %{
         config: config,
         install_template: install_template,
         install_result: effective_install_result(install_result, bundle_result),
         authoring_result: bundle_result,
         bootstrap_install_result: install_result,
         installation_ref: bundle_result.installation_ref,
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

  defp ensure_installation(%Config{} = config, install_template) do
    context = AppKitContext.bootstrap_context(config)

    case call_installation_surface(:create_installation, [context, install_template]) do
      {:ok, install_result} ->
        {:ok, install_result}

      {:error, %SurfaceError{code: "pack_registration_not_found"}} ->
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

  defp import_authoring_bundle(%Config{} = config, nil, bundle_import) do
    call_installation_surface(:import_authoring_bundle, [
      AppKitContext.bootstrap_context(config),
      bundle_import
    ])
  end

  defp import_authoring_bundle(%Config{} = config, install_result, bundle_import) do
    call_installation_surface(:import_authoring_bundle, [
      AppKitContext.product_context(config, install_result.installation_ref),
      bundle_import
    ])
  end

  defp effective_install_result(nil, bundle_result), do: bundle_result
  defp effective_install_result(install_result, _bundle_result), do: install_result

  # InstallationSurface dispatches to a runtime-configured backend in product hosts.
  defp call_installation_surface(function, args) do
    apply(InstallationSurface, function, args)
  end
end
