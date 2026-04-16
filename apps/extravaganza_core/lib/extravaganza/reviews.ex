defmodule Extravaganza.Reviews do
  @moduledoc """
  Product-local review commands over AppKit.
  """

  alias AppKit.OperatorSurface
  alias Extravaganza.{Config, ProductSurface}

  @spec review_run(AppKit.Core.RunRef.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def review_run(run_ref, evidence_attrs, opts \\ [])
      when is_map(evidence_attrs) and is_list(opts) do
    config = Config.load(opts)

    OperatorSurface.review_run(
      run_ref,
      evidence_attrs,
      ProductSurface.operator_opts(config, opts)
    )
  end
end
