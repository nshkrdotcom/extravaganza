defmodule Extravaganza.Operators do
  @moduledoc """
  Product-local operator detail, action, trace, and lease facade over AppKit.
  """

  alias AppKit.Core.{
    ExecutionRef,
    OperatorActionRef,
    OperatorActionRequest,
    RequestContext,
    SubjectRef,
    SubjectRuntimeProjection
  }

  alias AppKit.{OperatorSurface, WorkSurface}
  alias Extravaganza.{CodingOpsTemplates, LineageSummary, ProductSurface}

  @spec subject_detail(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def subject_detail(subject_id, opts \\ []) when is_binary(subject_id) and is_list(opts) do
    with_bootstrapped_subject(subject_id, opts, fn config, context, subject_ref ->
      query_opts = ProductSurface.work_query_opts(config, opts)
      operator_opts = ProductSurface.operator_opts(config, opts)

      with {:ok, subject} <- WorkSurface.get_subject(context, subject_ref, query_opts),
           {:ok, actions} <-
             OperatorSurface.available_actions(context, subject_ref, operator_opts),
           {:ok, timeline} <- OperatorSurface.timeline(context, subject_ref, operator_opts) do
        lineage_execution_ref = LineageSummary.lineage_execution_ref(subject)

        {unified_trace, trace_error} =
          fetch_unified_trace(context, lineage_execution_ref, operator_opts)

        lineage_summary = LineageSummary.build(subject, timeline, unified_trace)

        {:ok,
         %{
           subject: subject,
           actions: actions,
           timeline: timeline,
           unified_trace: unified_trace,
           trace_error: trace_error,
           lineage_summary: lineage_summary
         }}
      end
    end)
  end

  @spec runtime_projection(String.t(), keyword()) ::
          {:ok, SubjectRuntimeProjection.t()} | {:error, term()}
  def runtime_projection(subject_id, opts \\ []) when is_binary(subject_id) and is_list(opts) do
    with_bootstrapped_subject(subject_id, opts, fn config, context, subject_ref ->
      WorkSurface.get_runtime_projection(
        context,
        subject_ref,
        ProductSurface.work_query_opts(config, opts)
      )
    end)
  end

  @spec source_publication_preview(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def source_publication_preview(subject_id, opts \\ [])
      when is_binary(subject_id) and is_list(opts) do
    with {:ok, projection} <- runtime_projection(subject_id, opts) do
      {:ok, CodingOpsTemplates.source_publication_preview(projection)}
    end
  end

  @spec apply_action(String.t(), atom() | String.t(), map(), keyword()) ::
          {:ok, AppKit.Core.ActionResult.t()} | {:error, term()}
  def apply_action(subject_id, action_kind, attrs \\ %{}, opts \\ [])
      when is_binary(subject_id) and is_map(attrs) and is_list(opts) do
    with_bootstrapped_subject(subject_id, opts, fn config, context, subject_ref ->
      with {:ok, action_request} <- action_request(subject_ref, action_kind, attrs) do
        OperatorSurface.apply_action(
          context,
          subject_ref,
          action_request,
          ProductSurface.operator_opts(config, opts)
        )
      end
    end)
  end

  @spec issue_read_lease(String.t(), keyword()) ::
          {:ok, AppKit.Core.ReadLease.t()} | {:error, term()}
  def issue_read_lease(subject_id, opts \\ []) when is_binary(subject_id) and is_list(opts) do
    with_lineage_execution(subject_id, opts, fn config, context, execution_ref ->
      OperatorSurface.issue_read_lease(
        context,
        execution_ref,
        ProductSurface.operator_opts(config, opts)
      )
    end)
  end

  @spec issue_stream_attach_lease(String.t(), keyword()) ::
          {:ok, AppKit.Core.StreamAttachLease.t()} | {:error, term()}
  def issue_stream_attach_lease(subject_id, opts \\ [])
      when is_binary(subject_id) and is_list(opts) do
    with_current_execution(subject_id, opts, fn config, context, execution_ref ->
      OperatorSurface.issue_stream_attach_lease(
        context,
        execution_ref,
        ProductSurface.operator_opts(config, opts)
      )
    end)
  end

  defp with_lineage_execution(subject_id, opts, callback) when is_function(callback, 3) do
    with_bootstrapped_subject(subject_id, opts, fn config, context, subject_ref ->
      query_opts = ProductSurface.work_query_opts(config, opts)

      with {:ok, subject} <- WorkSurface.get_subject(context, subject_ref, query_opts),
           %ExecutionRef{} = execution_ref <- LineageSummary.lineage_execution_ref(subject) do
        callback.(config, context, execution_ref)
      else
        nil -> {:error, :missing_lineage_execution}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp with_current_execution(subject_id, opts, callback) when is_function(callback, 3) do
    with_bootstrapped_subject(subject_id, opts, fn config, context, subject_ref ->
      query_opts = ProductSurface.work_query_opts(config, opts)

      with {:ok, subject} <- WorkSurface.get_subject(context, subject_ref, query_opts),
           %ExecutionRef{} = execution_ref <- subject.current_execution_ref do
        callback.(config, context, execution_ref)
      else
        nil -> {:error, :missing_current_execution}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp with_bootstrapped_subject(subject_id, opts, callback) when is_function(callback, 3) do
    with {:ok, %{config: config, context: context}} <- ProductSurface.bootstrapped_context(opts),
         {:ok, subject_ref} <-
           SubjectRef.new(%{id: subject_id, subject_kind: config.work_class_kind}) do
      callback.(config, context, subject_ref)
    end
  end

  defp fetch_unified_trace(
         %RequestContext{} = context,
         %ExecutionRef{} = execution_ref,
         operator_opts
       ) do
    case OperatorSurface.get_unified_trace(context, execution_ref, operator_opts) do
      {:ok, trace} -> {trace, nil}
      {:error, reason} -> {nil, reason}
    end
  end

  defp fetch_unified_trace(%RequestContext{}, nil, _operator_opts), do: {nil, nil}

  defp action_request(%SubjectRef{} = subject_ref, action_kind, attrs) when is_map(attrs) do
    action_kind = normalize_action_kind(action_kind)

    with {:ok, action_ref} <-
           OperatorActionRef.new(%{
             id: "#{subject_ref.id}:#{action_kind}",
             action_kind: action_kind,
             subject_ref: subject_ref
           }) do
      OperatorActionRequest.new(%{
        action_ref: action_ref,
        params: action_params(attrs),
        reason: map_value(attrs, :reason),
        metadata: %{"product" => "extravaganza"}
      })
    end
  end

  defp action_params(attrs) when is_map(attrs) do
    attrs
    |> Map.new()
    |> Map.delete(:reason)
    |> Map.delete("reason")
  end

  defp normalize_action_kind(action_kind) when is_atom(action_kind),
    do: Atom.to_string(action_kind)

  defp normalize_action_kind(action_kind) when is_binary(action_kind), do: action_kind

  defp map_value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
