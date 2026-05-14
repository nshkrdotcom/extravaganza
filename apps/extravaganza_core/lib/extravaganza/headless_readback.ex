defmodule Extravaganza.HeadlessReadback do
  @moduledoc false

  alias AppKit.Core.RuntimeReadback.RuntimeRunDetail

  @evidence_coverage_kinds ~w[
    dispatch
    credential_preflight
    authority_decision
    provider_request_response
    lower_run
    hook
    workspace_action
    review_decision
    source_publication
  ]

  @timeline_coverage_kinds ~w[
    scheduler_tick
    refresh_request
    source_sync
    candidate_admission
    candidate_rejection
    dispatch
    retry
    cancellation
    codex_update
    hook
    publication
    reconciliation
  ]

  @spec evidence_chain(struct()) :: map()
  def evidence_chain(%RuntimeRunDetail{} = run) do
    run_data = RuntimeRunDetail.dump(run)
    runtime_row = Map.get(run_data, "runtime_row", %{})
    extensions = Map.get(runtime_row, "extensions", %{})
    run_ref = Map.get(run_data, "run_ref")
    evidence_coverage = evidence_coverage(run_data, runtime_row, extensions)

    %{
      "schema_ref" => "headless_evidence_chain.v1",
      "schema_version" => 1,
      "evidence_chain_ref" => "evidence-chain:#{safe_suffix(run_ref)}",
      "run_ref" => run_ref,
      "subject_ref" => Map.get(runtime_row, "subject_ref"),
      "runtime_profile_ref" => get_in(extensions, ["governance", "runtime_profile_ref"]),
      "governance" => Map.get(extensions, "governance", %{}),
      "lower" => Map.get(extensions, "lower_envelope", %{}),
      "lower_receipt" => Map.get(extensions, "lower_receipt", %{}),
      "retry_receipts" => Map.get(extensions, "retry_receipts", []),
      "incident_bundles" => Map.get(extensions, "incident_bundles", []),
      "acceptance" => Map.get(extensions, "acceptance", %{}),
      "source_publication" => Map.get(extensions, "source_publication", %{}),
      "evidence_coverage" => evidence_coverage,
      "evidence_coverage_gaps" => evidence_coverage_gaps(evidence_coverage),
      "events" => Map.get(run_data, "events", []),
      "diagnostics" => Map.get(run_data, "diagnostics", [])
    }
    |> compact()
    |> Map.put("evidence_coverage_gaps", evidence_coverage_gaps(evidence_coverage))
  end

  @spec event_page(struct(), map()) :: map()
  def event_page(%RuntimeRunDetail{} = run, params \\ %{}) when is_map(params) do
    run_data = RuntimeRunDetail.dump(run)
    entries = Map.get(run_data, "events", [])
    timeline_coverage = timeline_coverage(entries)

    %{
      "schema_ref" => "headless_events.v1",
      "schema_version" => 1,
      "event_page_ref" => "event-page:#{safe_suffix(Map.get(run_data, "run_ref"))}",
      "run_ref" => Map.get(run_data, "run_ref"),
      "entries" => entries,
      "timeline_coverage" => timeline_coverage,
      "timeline_coverage_gaps" => timeline_coverage_gaps(timeline_coverage),
      "page" => %{
        "page_size" => length(entries),
        "cursor" => Map.get(params, "cursor") || Map.get(params, :cursor),
        "total_entries" => length(entries)
      }
    }
    |> compact()
    |> Map.put("timeline_coverage_gaps", timeline_coverage_gaps(timeline_coverage))
  end

  defp compact(%{} = map), do: Map.reject(map, fn {_key, value} -> value in [nil, %{}, []] end)

  defp evidence_coverage(run_data, runtime_row, extensions) do
    %{
      "dispatch" => dispatch_evidence(run_data, runtime_row),
      "credential_preflight" => Map.get(extensions, "credential_preflight"),
      "authority_decision" => authority_decision_evidence(extensions),
      "provider_request_response" => Map.get(extensions, "provider_request_response"),
      "lower_run" => lower_run_evidence(extensions),
      "hook" => hook_evidence(run_data),
      "workspace_action" => workspace_action_evidence(run_data, runtime_row),
      "review_decision" => Map.get(extensions, "review_decision"),
      "source_publication" => Map.get(extensions, "source_publication")
    }
    |> compact()
    |> normalize_coverage_value()
  end

  defp evidence_coverage_gaps(coverage) when is_map(coverage) do
    Enum.reject(@evidence_coverage_kinds, &Map.has_key?(coverage, &1))
  end

  defp timeline_coverage(entries) when is_list(entries) do
    @timeline_coverage_kinds
    |> Map.new(fn category ->
      category_events =
        entries
        |> Enum.filter(&timeline_category_event?(&1, category))
        |> Enum.sort_by(&Map.get(&1, "event_seq", 0))

      {category, timeline_category_evidence(category_events)}
    end)
    |> compact()
  end

  defp timeline_coverage_gaps(coverage) when is_map(coverage) do
    Enum.reject(@timeline_coverage_kinds, &Map.has_key?(coverage, &1))
  end

  defp timeline_category_evidence([]), do: %{}

  defp timeline_category_evidence(events) do
    %{
      "event_refs" => events |> Enum.map(&Map.get(&1, "event_ref")) |> Enum.reject(&is_nil/1),
      "event_kinds" =>
        events
        |> Enum.map(&Map.get(&1, "event_kind"))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq(),
      "event_count" => length(events)
    }
    |> compact()
  end

  defp timeline_category_event?(%{} = event, category) do
    event
    |> Map.get("event_kind", "")
    |> timeline_category_kind?(category)
  end

  defp timeline_category_event?(_event, _category), do: false

  defp timeline_category_kind?("scheduler.tick.started", "scheduler_tick"), do: true
  defp timeline_category_kind?("refresh.requested", "refresh_request"), do: true
  defp timeline_category_kind?("source.sync.completed", "source_sync"), do: true
  defp timeline_category_kind?("candidate.admitted", "candidate_admission"), do: true
  defp timeline_category_kind?("candidate.rejected", "candidate_rejection"), do: true
  defp timeline_category_kind?("dispatch.started", "dispatch"), do: true
  defp timeline_category_kind?("codex.agent_message.updated", "codex_update"), do: true

  defp timeline_category_kind?(event_kind, "retry") when is_binary(event_kind),
    do: String.starts_with?(event_kind, "retry.")

  defp timeline_category_kind?(event_kind, "cancellation") when is_binary(event_kind),
    do: String.starts_with?(event_kind, "cancel.")

  defp timeline_category_kind?(event_kind, "hook") when is_binary(event_kind),
    do: String.starts_with?(event_kind, "workspace.hook.")

  defp timeline_category_kind?(event_kind, "publication") when is_binary(event_kind),
    do: String.starts_with?(event_kind, "source.publication.")

  defp timeline_category_kind?(event_kind, "reconciliation") when is_binary(event_kind),
    do: String.starts_with?(event_kind, "reconciliation.")

  defp timeline_category_kind?(_event_kind, _category), do: false

  defp dispatch_evidence(run_data, runtime_row) do
    refs =
      [
        Map.get(run_data, "run_ref"),
        Map.get(runtime_row, "execution_ref"),
        Map.get(runtime_row, "workflow_ref")
      ]
      |> Enum.reject(&is_nil/1)

    %{
      "refs" => refs,
      "event_refs" => event_refs(run_data, &(&1 == "run_started")),
      "state" => Map.get(runtime_row, "state"),
      "status_reason" => Map.get(runtime_row, "status_reason")
    }
    |> compact()
  end

  defp authority_decision_evidence(extensions) do
    extensions
    |> Map.get("governance", %{})
    |> Map.take([
      "authority_ref",
      "decision_ref",
      "runtime_profile_ref",
      "runtime_profile_kind",
      "connector_manifest_ref",
      "connector_manifest_state",
      "capability_negotiation_ref"
    ])
    |> compact()
  end

  defp lower_run_evidence(extensions) do
    lower_envelope = Map.get(extensions, "lower_envelope", %{})
    lower_receipt = Map.get(extensions, "lower_receipt", %{})

    %{
      "lower_request_ref" => Map.get(lower_envelope, "lower_request_ref"),
      "lower_receipt_ref" => Map.get(lower_receipt, "lower_receipt_ref"),
      "lower_runtime_kind" => Map.get(lower_envelope, "lower_runtime_kind"),
      "capability_id" => Map.get(lower_envelope, "capability_id"),
      "attempt_ref" => Map.get(lower_receipt, "attempt_ref"),
      "status" => Map.get(lower_receipt, "status")
    }
    |> compact()
  end

  defp hook_evidence(run_data) do
    hook_events = matching_events(run_data, &String.starts_with?(&1, "workspace.hook."))

    %{
      "event_refs" => Enum.map(hook_events, &Map.get(&1, "event_ref")) |> Enum.reject(&is_nil/1),
      "hook_refs" =>
        hook_events
        |> Enum.map(&get_in(&1, ["extensions", "hook_receipt", "hook_ref"]))
        |> Enum.reject(&is_nil/1),
      "stages" =>
        hook_events
        |> Enum.map(&get_in(&1, ["extensions", "hook_receipt", "stage"]))
        |> Enum.reject(&is_nil/1)
    }
    |> compact()
  end

  defp workspace_action_evidence(run_data, runtime_row) do
    workspace_events = matching_events(run_data, &String.starts_with?(&1, "workspace."))

    %{
      "workspace_ref" => Map.get(runtime_row, "workspace_ref"),
      "event_refs" =>
        workspace_events |> Enum.map(&Map.get(&1, "event_ref")) |> Enum.reject(&is_nil/1)
    }
    |> compact()
  end

  defp event_refs(run_data, predicate) do
    run_data
    |> matching_events(predicate)
    |> Enum.map(&Map.get(&1, "event_ref"))
    |> Enum.reject(&is_nil/1)
  end

  defp matching_events(run_data, predicate) when is_function(predicate, 1) do
    run_data
    |> Map.get("events", [])
    |> Enum.filter(fn
      %{} = event -> event |> Map.get("event_kind", "") |> predicate.()
      _other -> false
    end)
    |> Enum.sort_by(&Map.get(&1, "event_seq", 0))
  end

  defp normalize_coverage_value(%{} = map) do
    Map.new(map, fn {key, value} -> {key, normalize_coverage_field(key, value)} end)
  end

  defp normalize_coverage_value(values) when is_list(values),
    do: Enum.map(values, &normalize_coverage_value/1)

  defp normalize_coverage_value(value), do: value

  defp normalize_coverage_field(key, "true") when is_binary(key) do
    if String.ends_with?(key, "?"), do: true, else: "true"
  end

  defp normalize_coverage_field(key, "false") when is_binary(key) do
    if String.ends_with?(key, "?"), do: false, else: "false"
  end

  defp normalize_coverage_field(_key, value), do: normalize_coverage_value(value)

  defp safe_suffix(nil), do: "unknown"

  defp safe_suffix(value) when is_binary(value) do
    value
    |> String.replace("://", ":")
    |> String.replace("/", ":")
  end
end

defmodule Extravaganza.Presenters.EvidencePresenter do
  @moduledoc "Shared evidence-chain presenter."

  alias Extravaganza.HeadlessJSON

  @spec present(map(), keyword()) :: map()
  def present(chain, opts \\ []) when is_map(chain) do
    %{
      "schema_ref" => "headless_evidence_chain.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" => HeadlessJSON.sanitize(chain)
    }
  end
end

defmodule Extravaganza.Presenters.EventPresenter do
  @moduledoc "Shared event-page presenter."

  alias Extravaganza.HeadlessJSON

  @spec present_page(map(), keyword()) :: map()
  def present_page(page, opts \\ []) when is_map(page) do
    %{
      "schema_ref" => "headless_events.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" => HeadlessJSON.sanitize(page)
    }
  end
end
