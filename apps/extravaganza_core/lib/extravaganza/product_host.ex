defmodule Extravaganza.ProductHost do
  @moduledoc """
  Product-local operator host facade over the current AppKit surfaces.
  """

  alias Extravaganza.{
    HeadlessLiveExamples,
    HeadlessSameRunSmoke,
    HeadlessSurface,
    Operators,
    Queries,
    Reviews,
    Sources,
    Workflows
  }

  @spec state_snapshot(map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def state_snapshot(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    HeadlessSurface.state_snapshot(params, opts)
  end

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

  @spec same_run_smoke(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def same_run_smoke(opts \\ []) do
    HeadlessSameRunSmoke.run(opts)
  end

  @spec run_status(AppKit.Core.RunRef.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_status(run_ref, attrs \\ %{}, opts \\ [])
      when is_map(attrs) and is_list(opts) do
    Queries.run_status(run_ref, attrs, opts)
  end

  @spec run_detail(String.t(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def run_detail(run_id, attrs \\ %{}, opts \\ [])
      when is_binary(run_id) and is_map(attrs) and is_list(opts) do
    HeadlessSurface.run_detail(run_id, attrs, opts)
  end

  @spec evidence_chain(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def evidence_chain(run_id, attrs \\ %{}, opts \\ [])
      when is_binary(run_id) and is_map(attrs) and is_list(opts) do
    HeadlessSurface.evidence_chain(run_id, attrs, opts)
  end

  @spec events(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def events(params \\ %{}, opts \\ []) when is_map(params) and is_list(opts) do
    HeadlessSurface.events(params, opts)
  end

  @spec request_refresh(map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def request_refresh(attrs \\ %{}, opts \\ []) when is_map(attrs) and is_list(opts) do
    HeadlessSurface.request_refresh(attrs, opts)
  end

  @spec request_control(String.t(), atom() | String.t(), map(), keyword()) ::
          {:ok, struct()} | {:error, term()}
  def request_control(subject_id, action, attrs \\ %{}, opts \\ [])
      when is_binary(subject_id) and is_map(attrs) and is_list(opts) do
    HeadlessSurface.request_control(subject_id, action, attrs, opts)
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
    HeadlessSurface.source_publication_preview(subject_id, opts)
  end

  @spec sync_linear_source(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def sync_linear_source(source_page, opts \\ []) when is_map(source_page) and is_list(opts) do
    Sources.sync_linear_issues(source_page, opts)
  end

  @spec sync_linear_issue(map(), keyword()) ::
          {:ok, AppKit.Core.SubjectDetail.t()} | {:error, term()}
  def sync_linear_issue(issue, opts \\ []) when is_map(issue) and is_list(opts) do
    Sources.sync_linear_issue(issue, opts)
  end

  @spec live_linear_source_example(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def live_linear_source_example(opts \\ []), do: HeadlessLiveExamples.run(:linear_source, opts)

  @spec live_linear_current_states_example(keyword() | map()) ::
          {:ok, map()} | {:error, term()}
  def live_linear_current_states_example(opts \\ []),
    do: HeadlessLiveExamples.run(:linear_current_states, opts)

  @spec live_codex_turn_example(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def live_codex_turn_example(opts \\ []), do: HeadlessLiveExamples.run(:codex_turn, opts)

  @spec live_linear_publication_example(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def live_linear_publication_example(opts \\ []),
    do: HeadlessLiveExamples.run(:linear_publication, opts)

  @spec live_linear_graphql_tool_example(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def live_linear_graphql_tool_example(opts \\ []),
    do: HeadlessLiveExamples.run(:linear_graphql_tool, opts)

  @spec live_github_evidence_example(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def live_github_evidence_example(opts \\ []),
    do: HeadlessLiveExamples.run(:github_evidence, opts)

  @spec live_github_pr_cleanup_example(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def live_github_pr_cleanup_example(opts \\ []),
    do: HeadlessLiveExamples.run(:github_pr_cleanup, opts)

  @spec live_smoke(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def live_smoke(opts \\ []), do: HeadlessLiveExamples.run(:smoke, opts)

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
