defmodule Extravaganza.ThinHost do
  @moduledoc """
  Compatibility wrapper over the product-local AppKit facades.
  """

  alias Extravaganza.{Queries, Reviews, Workflows}

  @spec start_run(map(), keyword()) :: {:ok, AppKit.Core.Result.t()} | {:error, term()}
  def start_run(domain_call, opts \\ []) when is_map(domain_call) and is_list(opts) do
    Workflows.start_run(domain_call, opts)
  end

  @spec run_status(AppKit.Core.RunRef.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_status(run_ref, attrs \\ %{}, opts \\ [])
      when is_map(attrs) and is_list(opts) do
    Queries.run_status(run_ref, attrs, opts)
  end

  @spec review_run(AppKit.Core.RunRef.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def review_run(run_ref, evidence_attrs, opts \\ [])
      when is_map(evidence_attrs) and is_list(opts) do
    Reviews.review_run(run_ref, evidence_attrs, opts)
  end
end
