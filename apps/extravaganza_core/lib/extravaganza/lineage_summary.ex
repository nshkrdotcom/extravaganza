defmodule Extravaganza.LineageSummary do
  @moduledoc false

  alias AppKit.Core.{ExecutionRef, SubjectDetail, UnifiedTrace}

  @spec build(SubjectDetail.t(), list(), UnifiedTrace.t() | nil) :: map()
  def build(%SubjectDetail{} = subject, timeline, unified_trace) when is_list(timeline) do
    execution_ref = lineage_execution_ref(subject)
    payload = Map.get(subject, :payload, %{})

    trace_id =
      (unified_trace && unified_trace.trace_id) || map_value(payload, :latest_execution_trace_id)

    %{
      execution_ref: execution_ref,
      current_dispatch_state: execution_ref && normalize_value(execution_ref.dispatch_state),
      trace_id: normalize_value(trace_id),
      markers: markers(subject, execution_ref, timeline, unified_trace, normalize_value(trace_id))
    }
  end

  @spec lineage_execution_ref(SubjectDetail.t()) :: ExecutionRef.t() | nil
  def lineage_execution_ref(%SubjectDetail{
        current_execution_ref: %ExecutionRef{} = execution_ref
      }),
      do: execution_ref

  def lineage_execution_ref(%SubjectDetail{} = subject) do
    payload = Map.get(subject, :payload, %{})

    with execution_id when is_binary(execution_id) <- map_value(payload, :latest_execution_id),
         dispatch_state <- normalize_value(map_value(payload, :latest_execution_dispatch_state)),
         {:ok, execution_ref} <-
           ExecutionRef.new(%{
             id: execution_id,
             subject_ref: subject.subject_ref,
             dispatch_state: dispatch_state
           }) do
      execution_ref
    else
      _other -> nil
    end
  end

  defp markers(
         %SubjectDetail{} = subject,
         execution_ref,
         timeline,
         %UnifiedTrace{} = unified_trace,
         trace_id
       ) do
    freshness_values =
      unified_trace.steps
      |> Enum.map(&normalize_value(&1.freshness))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    payload_markers =
      unified_trace.steps
      |> Enum.flat_map(&step_markers/1)

    [
      marker("Lifecycle state", normalize_value(subject.lifecycle_state)),
      marker("Dispatch state", execution_ref && normalize_value(execution_ref.dispatch_state)),
      marker("Trace anchor", trace_id)
      | Enum.map(freshness_values, &marker("Freshness", &1))
    ]
    |> Kernel.++(payload_markers)
    |> Kernel.++(timeline_markers(timeline))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.label, &1.value})
  end

  defp markers(%SubjectDetail{} = subject, execution_ref, timeline, nil, trace_id) do
    [
      marker("Lifecycle state", normalize_value(subject.lifecycle_state)),
      marker("Dispatch state", execution_ref && normalize_value(execution_ref.dispatch_state)),
      marker("Trace anchor", trace_id)
    ]
    |> Kernel.++(timeline_markers(timeline))
    |> Enum.reject(&is_nil/1)
  end

  defp step_markers(step) do
    payload = normalize_map(step.payload)
    fact_payload = normalize_map(map_value(payload, :payload))
    payload = payload |> Map.drop([:payload, "payload"]) |> Map.merge(fact_payload)

    [
      marker("Dispatch state", map_value(payload, :dispatch_state)),
      marker("Classification", map_value(payload, :classification)),
      marker("Reconcile wave", map_value(payload, :last_reconcile_wave_id)),
      marker("Supersedes execution", map_value(payload, :supersedes_execution_id)),
      marker("Join barrier", map_value(payload, :barrier_id)),
      marker("Join step", map_value(payload, :join_step_ref)),
      join_progress_marker(payload),
      invalidated_leases_marker(payload)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp invalidated_leases_marker(payload) do
    case map_value(payload, :invalidated_lease_ids) do
      ids when is_list(ids) and ids != [] ->
        marker("Invalidated leases", Integer.to_string(length(ids)))

      _other ->
        nil
    end
  end

  defp join_progress_marker(payload) do
    completed = map_value(payload, :completed_children)
    expected = map_value(payload, :expected_children)

    if is_integer(completed) and is_integer(expected) do
      marker("Join progress", "#{completed}/#{expected}")
    end
  end

  defp marker(_label, nil), do: nil
  defp marker(label, value), do: %{label: label, value: normalize_value(value)}

  defp timeline_markers(timeline) when is_list(timeline) do
    timeline
    |> Enum.flat_map(fn event ->
      payload = normalize_map(Map.get(event, :payload, %{}))

      [
        invalidated_leases_marker(payload)
      ]
      |> Enum.reject(&is_nil/1)
    end)
  end

  defp normalize_map(map) when is_map(map), do: Map.new(map)
  defp normalize_map(_other), do: %{}

  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_value(value) when is_boolean(value), do: to_string(value)
  defp normalize_value(value), do: value

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(_map, _key), do: nil
end
