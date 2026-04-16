defmodule Extravaganza.ThinHost do
  @moduledoc """
  Thin-host entrypoints that route AppKit surfaces through the existing
  mezzanine-backed adapters.
  """

  alias AppKit.OperatorSurface
  alias AppKit.WorkControl
  alias Extravaganza.Config
  alias Extravaganza.ProductBootstrap
  alias Mezzanine.Surfaces.ProgramSurface

  @spec start_run(map(), keyword()) :: {:ok, AppKit.Core.Result.t()} | {:error, term()}
  def start_run(domain_call, opts \\ []) when is_map(domain_call) and is_list(opts) do
    with {:ok, profile} <- ProductBootstrap.ensure_bootstrapped(opts) do
      WorkControl.start_run(domain_call, app_kit_opts(profile, opts))
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

  defp app_kit_opts(%{config: config, program: program, work_class: work_class}, opts) do
    program_id = ProgramSurface.program_id(program)
    work_class_id = ProgramSurface.work_class_id(work_class)

    Keyword.merge(
      [
        tenant_id: config.tenant_id,
        program_id: program_id,
        work_class_id: work_class_id,
        scope_id: "program/#{program_id}",
        work_backend: Mezzanine.AppKitBridge.WorkControlAdapter
      ],
      opts
    )
  end

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
