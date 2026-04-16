defmodule Extravaganza.ThinHost do
  @moduledoc """
  Thin-host entrypoints that route AppKit surfaces through the existing
  mezzanine-backed adapters.
  """

  alias AppKit.Core.RunRequest
  alias AppKit.{OperatorSurface, WorkControl, WorkSurface}
  alias Extravaganza.{AppKitContext, Config, ProductBootstrap}

  @spec start_run(map(), keyword()) :: {:ok, AppKit.Core.Result.t()} | {:error, term()}
  def start_run(domain_call, opts \\ []) when is_map(domain_call) and is_list(opts) do
    with {:ok, profile} <- ProductBootstrap.ensure_bootstrapped(opts),
         context = AppKitContext.product_context(profile.config, profile.installation_ref),
         {:ok, subject_ref} <- WorkSurface.ingest_subject(context, Map.new(domain_call)),
         {:ok, run_request} <- RunRequest.new(%{subject_ref: subject_ref}) do
      WorkControl.start_run(context, run_request, work_control_opts(profile.config, opts))
    end
  end

  @spec run_status(AppKit.Core.RunRef.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_status(run_ref, attrs \\ %{}, opts \\ [])
      when is_map(attrs) and is_list(opts) do
    config = Config.load(opts)
    OperatorSurface.run_status(run_ref, attrs, operator_opts(config, opts))
  end

  @spec review_run(AppKit.Core.RunRef.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def review_run(run_ref, evidence_attrs, opts \\ [])
      when is_map(evidence_attrs) and is_list(opts) do
    config = Config.load(opts)
    OperatorSurface.review_run(run_ref, evidence_attrs, operator_opts(config, opts))
  end

  defp work_control_opts(config, opts),
    do:
      Keyword.merge(
        [
          scope_id: AppKitContext.scope_id(config),
          work_backend: Mezzanine.AppKitBridge.WorkControlService
        ],
        opts
      )

  defp operator_opts(config, opts) do
    Keyword.merge(
      [
        tenant_id: config.tenant_id,
        config: %{operator_surface?: config.operator_surface_enabled?},
        operator_backend: Mezzanine.AppKitBridge.OperatorProjectionAdapter
      ],
      opts
    )
  end
end
