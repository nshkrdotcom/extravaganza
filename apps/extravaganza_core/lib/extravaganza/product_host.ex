defmodule Extravaganza.ProductHost do
  @moduledoc """
  Product-local operator host facade over the current AppKit surfaces.
  """

  alias Extravaganza.{Operators, Queries, Reviews, Workflows}

  @spec operator_queue(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def operator_queue(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    Queries.operator_queue(params, opts)
  end

  @spec pending_reviews(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def pending_reviews(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    Queries.pending_reviews(params, opts)
  end

  @spec start_run(map(), keyword()) :: {:ok, AppKit.Core.Result.t()} | {:error, term()}
  def start_run(domain_call, opts \\ []) when is_map(domain_call) and is_list(opts) do
    Workflows.start_run(domain_call, opts)
  end

  @spec run_status(AppKit.Core.RunRef.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_status(run_ref, attrs \\ %{}, opts \\ [])
      when is_map(attrs) and is_list(opts) do
    Queries.run_status(run_ref, attrs, opts)
  end

  @spec subject_detail(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def subject_detail(subject_id, opts \\ []) when is_binary(subject_id) and is_list(opts) do
    Operators.subject_detail(subject_id, opts)
  end

  @spec runtime_projection(String.t(), keyword()) ::
          {:ok, AppKit.Core.SubjectRuntimeProjection.t()} | {:error, term()}
  def runtime_projection(subject_id, opts \\ []) when is_binary(subject_id) and is_list(opts) do
    Operators.runtime_projection(subject_id, opts)
  end

  @spec source_publication_preview(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def source_publication_preview(subject_id, opts \\ [])
      when is_binary(subject_id) and is_list(opts) do
    Operators.source_publication_preview(subject_id, opts)
  end

  @spec apply_subject_action(String.t(), atom() | String.t(), map(), keyword()) ::
          {:ok, AppKit.Core.ActionResult.t()} | {:error, term()}
  def apply_subject_action(subject_id, action_kind, attrs \\ %{}, opts \\ [])
      when is_binary(subject_id) and is_map(attrs) and is_list(opts) do
    Operators.apply_action(subject_id, action_kind, attrs, opts)
  end

  @spec issue_read_lease(String.t(), keyword()) ::
          {:ok, AppKit.Core.ReadLease.t()} | {:error, term()}
  def issue_read_lease(subject_id, opts \\ []) when is_binary(subject_id) and is_list(opts) do
    Operators.issue_read_lease(subject_id, opts)
  end

  @spec issue_stream_attach_lease(String.t(), keyword()) ::
          {:ok, AppKit.Core.StreamAttachLease.t()} | {:error, term()}
  def issue_stream_attach_lease(subject_id, opts \\ [])
      when is_binary(subject_id) and is_list(opts) do
    Operators.issue_stream_attach_lease(subject_id, opts)
  end

  @spec review_run(AppKit.Core.RunRef.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def review_run(run_ref, evidence_attrs, opts \\ [])
      when is_map(evidence_attrs) and is_list(opts) do
    Reviews.review_run(run_ref, evidence_attrs, opts)
  end

  @spec record_review_decision(AppKit.Core.DecisionRef.t() | map(), map(), keyword()) ::
          {:ok, AppKit.Core.ActionResult.t()} | {:error, term()}
  def record_review_decision(review_identity, attrs \\ %{}, opts \\ [])
      when is_map(attrs) and is_list(opts) do
    Reviews.record_review_decision(review_identity, attrs, opts)
  end
end
