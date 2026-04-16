defmodule Extravaganza.ProductBootstrap do
  @moduledoc """
  Idempotent bootstrap of the Extravaganza default product profile through the
  northbound AppKit installation surface.
  """

  alias AppKit.InstallationSurface

  alias Extravaganza.{
    AppKitContext,
    Config,
    ProductInstallTemplate,
    ProductPack,
    RuntimeProvisioner
  }

  @spec ensure_bootstrapped(keyword() | map()) ::
          {:ok,
           %{
             config: Extravaganza.Config.t(),
             install_result: struct(),
             install_template: struct(),
             installation_ref: struct(),
             pack: map(),
             routing: map()
           }}
          | {:error, term()}
  def ensure_bootstrapped(overrides \\ []) do
    config = Config.load(overrides)
    install_template = ProductInstallTemplate.default(config)

    with {:ok, _runtime_surface} <- RuntimeProvisioner.ensure_runtime_surface(config),
         {:ok, install_result} <-
           InstallationSurface.create_installation(
             AppKitContext.bootstrap_context(config),
             install_template
           ) do
      {:ok,
       %{
         config: config,
         install_template: install_template,
         install_result: install_result,
         installation_ref: install_result.installation_ref,
         pack: %{
           slug: ProductPack.pack_slug(config),
           version: ProductPack.pack_version(config)
         },
         routing: AppKitContext.routing_metadata(config)
       }}
    end
  end
end
