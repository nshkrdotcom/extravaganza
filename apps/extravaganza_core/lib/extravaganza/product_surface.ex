defmodule Extravaganza.ProductSurface do
  @moduledoc false

  alias AppKit.Core.RequestContext
  alias Extravaganza.{AppKitContext, Config, ProductBootstrap}

  @spec bootstrapped_context(keyword()) ::
          {:ok, %{config: Config.t(), context: RequestContext.t(), profile: map()}}
          | {:error, term()}
  def bootstrapped_context(opts) when is_list(opts) do
    with {:ok, profile} <- ProductBootstrap.ensure_bootstrapped(opts) do
      {:ok,
       %{
         config: profile.config,
         context: AppKitContext.product_context(profile.config, profile.installation_ref),
         profile: profile
       }}
    end
  end

  @spec work_control_opts(Config.t(), keyword()) :: keyword()
  def work_control_opts(%Config{} = config, opts) when is_list(opts) do
    scoped_opts(config, opts)
  end

  @spec work_query_opts(Config.t(), keyword()) :: keyword()
  def work_query_opts(%Config{} = config, opts) when is_list(opts) do
    scoped_opts(config, opts)
  end

  @spec operator_opts(Config.t(), keyword()) :: keyword()
  def operator_opts(%Config{} = config, opts) when is_list(opts) do
    Keyword.merge(
      [
        tenant_id: config.tenant_id,
        config: %{operator_surface?: config.operator_surface_enabled?}
      ],
      opts
    )
  end

  defp scoped_opts(%Config{} = config, opts) when is_list(opts) do
    Keyword.merge([scope_id: AppKitContext.scope_id(config)], opts)
  end
end
