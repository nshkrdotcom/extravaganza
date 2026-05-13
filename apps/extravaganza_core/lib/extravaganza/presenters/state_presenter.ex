defmodule Extravaganza.Presenters.StatePresenter do
  @moduledoc "Shared queue/state presenter for browser and JSON output."

  alias AppKit.Core.RuntimeReadback.{Presenter, RuntimeStateSnapshot}
  alias Extravaganza.Presenters.JSONSupport

  @future_m2_slots %{
    "turns" => [],
    "budget_state" => %{"status" => "not_available"},
    "candidate_fact_refs" => [],
    "memory_proof_refs" => [],
    "agent_loop_diagnostics" => []
  }
  @running_states ~w[running]
  @claimed_states ~w[running queued in_flight accepted_active]
  @completed_states ~w[completed terminal_success]
  @atom_keys %{
    "attempt_ref" => :attempt_ref,
    "available" => :available,
    "cached_input_tokens" => :cached_input_tokens,
    "checking?" => :checking?,
    "claim_state" => :claim_state,
    "completion_state" => :completion_state,
    "blocker_refs" => :blocker_refs,
    "display_label" => :display_label,
    "dispatch_eligibility" => :dispatch_eligibility,
    "delay_ms" => :delay_ms,
    "delay_type" => :delay_type,
    "due_at" => :due_at,
    "error" => :error,
    "execution" => :execution,
    "execution_ref" => :execution_ref,
    "extensions" => :extensions,
    "id" => :id,
    "input_tokens" => :input_tokens,
    "last_error_ref" => :last_error_ref,
    "last_event" => :last_event,
    "last_event_at" => :last_event_at,
    "last_message" => :last_message,
    "last_refresh_command_ref" => :last_refresh_command_ref,
    "last_synced_at" => :last_synced_at,
    "limit_id" => :limit_id,
    "max" => :max,
    "metadata" => :metadata,
    "name" => :name,
    "next_poll_at" => :next_poll_at,
    "orchestrator_state" => :orchestrator_state,
    "output_tokens" => :output_tokens,
    "path_redacted?" => :path_redacted?,
    "poll_interval_ms" => :poll_interval_ms,
    "polling_state" => :polling_state,
    "pre_dispatch_revalidation" => :pre_dispatch_revalidation,
    "profile_refs" => :profile_refs,
    "projection_profile_ref" => :projection_profile_ref,
    "provider_refs" => :provider_refs,
    "rate_limits" => :rate_limits,
    "reason" => :reason,
    "remaining" => :remaining,
    "reset_at" => :reset_at,
    "retry_ref" => :retry_ref,
    "retry_rows" => :retry_rows,
    "rows" => :rows,
    "run_ref" => :run_ref,
    "runtime" => :runtime,
    "runtime_profile_kind" => :runtime_profile_kind,
    "runtime_profile_ref" => :runtime_profile_ref,
    "scheduled_at" => :scheduled_at,
    "seconds_running" => :seconds_running,
    "session_id" => :session_id,
    "session_ref" => :session_ref,
    "source" => :source,
    "source_ref" => :source_ref,
    "source_sync" => :source_sync,
    "source_event_ref" => :source_event_ref,
    "state" => :state,
    "state_mapping" => :state_mapping,
    "status" => :status,
    "staleness_ms" => :staleness_ms,
    "subject_ref" => :subject_ref,
    "tokens" => :tokens,
    "total_input_tokens" => :total_input_tokens,
    "total_output_tokens" => :total_output_tokens,
    "total_tokens" => :total_tokens,
    "updated_at" => :updated_at,
    "window" => :window,
    "workflow_ref" => :workflow_ref,
    "workspace_ref" => :workspace_ref
  }

  @spec present(struct() | map(), keyword()) :: map()
  def present(value, opts \\ [])

  def present(%RuntimeStateSnapshot{} = snapshot, opts) do
    snapshot
    |> Presenter.present(opts)
    |> put_in(["schema_ref"], "headless_state_snapshot.v1")
    |> update_in(["data"], &with_future_slots/1)
    |> JSONSupport.normalize()
  end

  def present(%{} = state, opts) do
    %{
      "schema_ref" => "headless_state_snapshot.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" => with_future_slots(stringify(state))
    }
  end

  @spec present_queue(map(), keyword()) :: map()
  def present_queue(%{page: page} = queue, _opts \\ []) do
    entries = page |> Map.get(:entries, []) |> Enum.map(&with_queue_entry_eligibility/1)

    %{
      entries: entries,
      stats: Map.get(queue, :stats, %{}),
      total_count: Map.get(page, :total_count, length(entries)),
      has_more?: Map.get(page, :has_more, false),
      next_cursor: Map.get(page, :next_cursor),
      page: %{
        page_size: length(entries),
        cursor: Map.get(page, :next_cursor),
        total_entries: Map.get(page, :total_count, length(entries))
      },
      future_m2: @future_m2_slots
    }
  end

  def future_m2_slots, do: @future_m2_slots

  defp with_queue_entry_eligibility(%{payload: payload} = entry) when is_map(payload) do
    %{entry | payload: Map.put_new(payload, :dispatch_eligibility, dispatch_eligibility(payload))}
  end

  defp with_queue_entry_eligibility(entry), do: entry

  defp dispatch_eligibility(payload) do
    pre_dispatch_revalidation = map_value(payload, "pre_dispatch_revalidation")
    state_mapping = map_value(payload, "state_mapping") || %{}
    reason = map_value(state_mapping, "reason")
    blocker_refs = list_value(payload, "blocker_refs")

    cond do
      is_map(pre_dispatch_revalidation) ->
        pre_dispatch_eligibility(pre_dispatch_revalidation, blocker_refs)

      reason == "blocked_by_non_terminal" ->
        %{
          eligible?: false,
          reason: "non_terminal_dependency",
          blocker_refs: blocker_refs
        }

      reason in ["not_routed_to_worker", "source_state_not_dispatchable", "unknown_source_state"] ->
        %{eligible?: false, reason: reason}

      reason in ["dispatchable", "active", "candidate"] ->
        %{eligible?: true, reason: "dispatchable"}

      true ->
        %{eligible?: true, reason: "not_blocked_in_product_queue"}
    end
  end

  defp pre_dispatch_eligibility(revalidation, blocker_refs) do
    status = map_value(revalidation, "status")
    reason = map_value(revalidation, "reason") || "pre_dispatch_revalidation"

    %{
      eligible?: status == "accepted",
      reason: reason,
      blocker_refs: blocker_refs,
      pre_dispatch_revalidation: revalidation
    }
  end

  defp with_future_slots(data) when is_map(data) do
    data = Map.merge(@future_m2_slots, data)
    Map.put_new(data, "symphony_orchestrator_state", symphony_orchestrator_state(data))
  end

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp symphony_orchestrator_state(data) do
    rows = list_value(data, "rows")

    %{
      "mapped_from" => "appkit_runtime_readback",
      "counts" => counts(rows, data),
      "running" => rows |> Enum.filter(&running?/1) |> Enum.map(&running_summary/1),
      "claimed" => rows |> Enum.filter(&claimed?/1) |> Enum.map(&map_value(&1, "subject_ref")),
      "retry_attempts" => data |> list_value("retry_rows") |> Enum.map(&retry_attempt/1),
      "retrying" => data |> list_value("retry_rows") |> Enum.map(&retrying_summary/1),
      "completed" =>
        rows |> Enum.filter(&completed?/1) |> Enum.map(&map_value(&1, "subject_ref")),
      "codex_totals" => codex_totals(map_value(data, "token_totals")),
      "codex_rate_limits" => data |> list_value("rate_limits") |> Enum.map(&rate_limit/1),
      "polling" => polling(map_value(data, "polling_state")),
      "slots" => first_row_extension(rows, "slots"),
      "profile_refs" => first_row_extension(rows, "profile_refs"),
      "source_sync" => first_row_extension(rows, "source_sync"),
      "reconciliation_warnings" => reconciliation_warnings(data, rows)
    }
    |> compact_map()
  end

  defp counts(rows, data) do
    %{
      "running" => Enum.count(rows, &running?/1),
      "retrying" => length(list_value(data, "retry_rows")),
      "completed" => Enum.count(rows, &completed?/1)
    }
  end

  defp running?(row), do: state(row) in @running_states

  defp claimed?(row) do
    scheduler_value(row, "claim_state") == "claimed" or state(row) in @claimed_states
  end

  defp completed?(row) do
    scheduler_value(row, "completion_state") == "completed" or state(row) in @completed_states
  end

  defp running_summary(row) do
    %{
      "subject_ref" => map_value(row, "subject_ref"),
      "run_ref" => map_value(row, "run_ref"),
      "execution_ref" => map_value(row, "execution_ref"),
      "workflow_ref" => map_value(row, "workflow_ref"),
      "state" => state(row),
      "updated_at" => map_value(row, "updated_at"),
      "session_ref" => ref_summary(map_value(row, "session_ref")),
      "session_id" => session_id(row),
      "workspace_ref" => workspace_summary(map_value(row, "workspace_ref")),
      "provider_refs" => map_value(row, "provider_refs"),
      "token_totals" => maybe_codex_totals(map_value(row, "token_totals")),
      "turn_count" => integer_or_nil(orchestrator_value(row, "turn_count")),
      "started_at" => orchestrator_value(row, "started_at"),
      "last_event" => orchestrator_value(row, "last_event"),
      "last_message" => orchestrator_value(row, "last_message"),
      "last_event_at" => orchestrator_value(row, "last_event_at"),
      "tokens" => token_summary(row)
    }
    |> compact_map()
  end

  defp retry_attempt(row) do
    %{
      "retry_ref" => map_value(row, "retry_ref"),
      "attempt_ref" => map_value(row, "attempt_ref"),
      "status" => normalize_state(map_value(row, "status")),
      "reason" => map_value(row, "reason"),
      "scheduled_at" => map_value(row, "scheduled_at"),
      "due_at" => map_value(row, "due_at"),
      "next_due_at" => map_value(row, "due_at") || map_value(row, "scheduled_at"),
      "delay_ms" => map_value(row, "delay_ms"),
      "delay_type" => map_value(row, "delay_type"),
      "continuation?" => map_value(row, "continuation?"),
      "last_error_ref" => map_value(row, "last_error_ref")
    }
    |> compact_map()
  end

  defp retrying_summary(row) do
    %{
      "attempt" => map_value(row, "attempt_ref") || map_value(row, "retry_ref"),
      "due_at" => map_value(row, "due_at") || map_value(row, "scheduled_at"),
      "error" => map_value(row, "reason") || map_value(row, "error"),
      "status" => normalize_state(map_value(row, "status"))
    }
    |> compact_map()
  end

  defp codex_totals(nil), do: empty_codex_totals()

  defp codex_totals(totals) when is_map(totals) do
    %{
      "input_tokens" => integer_value(totals, "input_tokens", "total_input_tokens"),
      "output_tokens" => integer_value(totals, "output_tokens", "total_output_tokens"),
      "total_tokens" => integer_value(totals, "total_tokens", "total_tokens"),
      "seconds_running" => integer_value(totals, "seconds_running"),
      "source" => map_value(totals, "source")
    }
    |> compact_map()
    |> Map.merge(empty_codex_totals(), fn _key, value, _default -> value end)
  end

  defp codex_totals(_totals), do: empty_codex_totals()

  defp maybe_codex_totals(nil), do: nil
  defp maybe_codex_totals(totals), do: codex_totals(totals)

  defp empty_codex_totals do
    %{
      "input_tokens" => 0,
      "output_tokens" => 0,
      "total_tokens" => 0,
      "seconds_running" => 0
    }
  end

  defp rate_limit(row) do
    %{
      "limit_id" => map_value(row, "limit_id"),
      "name" => map_value(row, "name"),
      "remaining" => map_value(row, "remaining"),
      "reset_at" => map_value(row, "reset_at"),
      "window" => map_value(row, "window"),
      "source_event_ref" => map_value(row, "source_event_ref")
    }
    |> compact_map()
  end

  defp polling(nil), do: %{}

  defp polling(state) when is_map(state) do
    %{
      "checking?" => map_value(state, "checking?"),
      "last_refresh_command_ref" => map_value(state, "last_refresh_command_ref"),
      "next_poll_at" => map_value(state, "next_poll_at"),
      "poll_interval_ms" => map_value(state, "poll_interval_ms"),
      "staleness_ms" => map_value(state, "staleness_ms")
    }
    |> compact_map()
  end

  defp polling(_state), do: %{}

  defp ref_summary(nil), do: nil
  defp ref_summary(ref) when is_binary(ref), do: %{"id" => ref}
  defp ref_summary(ref) when is_map(ref), do: ref |> Map.take(["id", :id]) |> stringify()
  defp ref_summary(_ref), do: nil

  defp workspace_summary(nil), do: nil

  defp workspace_summary(ref) when is_map(ref) do
    %{
      "id" => map_value(ref, "id"),
      "display_label" => map_value(ref, "display_label"),
      "path_redacted?" => map_value(ref, "path_redacted?")
    }
    |> compact_map()
  end

  defp workspace_summary(_ref), do: nil

  defp session_id(row) do
    case map_value(row, "session_ref") do
      %{} = ref -> map_value(ref, "id")
      value when is_binary(value) -> value
      _value -> nil
    end
  end

  defp token_summary(row) do
    case map_value(row, "token_totals") || orchestrator_value(row, "tokens") do
      %{} = totals ->
        %{
          "input_tokens" => integer_value(totals, "input_tokens", "total_input_tokens"),
          "output_tokens" => integer_value(totals, "output_tokens", "total_output_tokens"),
          "total_tokens" => integer_value(totals, "total_tokens")
        }

      _value ->
        nil
    end
  end

  defp state(row), do: row |> map_value("state") |> normalize_state()

  defp scheduler_value(row, key) do
    extensions = map_value(row, "extensions")

    Enum.find_value(
      [
        ["orchestrator_state", key],
        ["runtime", "metadata", key],
        ["execution", "metadata", key],
        ["metadata", key]
      ],
      &nested_value(extensions, &1)
    )
    |> normalize_state()
  end

  defp orchestrator_value(row, key) do
    extensions = map_value(row, "extensions")

    Enum.find_value(
      [
        ["orchestrator_state", key],
        ["runtime", "metadata", key],
        ["execution", "metadata", key],
        ["metadata", key]
      ],
      &nested_value(extensions, &1)
    )
  end

  defp first_row_extension(rows, key) do
    Enum.find_value(rows, fn row ->
      value =
        row
        |> map_value("extensions")
        |> nested_value([key])

      if value in [nil, %{}, []], do: nil, else: value
    end)
  end

  defp reconciliation_warnings(data, rows) do
    diagnostic_warnings =
      data
      |> list_value("diagnostics")
      |> Enum.filter(&(map_value(&1, "severity") == "warning"))
      |> Enum.map(&warning_summary/1)

    row_warnings =
      rows
      |> Enum.flat_map(fn row ->
        row
        |> map_value("extensions")
        |> nested_value(["reconciliation_warnings"])
        |> case do
          values when is_list(values) -> values
          value when is_map(value) -> [value]
          _value -> []
        end
      end)
      |> Enum.map(&warning_summary/1)

    diagnostic_warnings ++ row_warnings
  end

  defp warning_summary(row) do
    %{
      "code" => map_value(row, "code"),
      "message" => map_value(row, "message"),
      "source_ref" => map_value(row, "source_ref")
    }
    |> compact_map()
  end

  defp nested_value(value, []), do: value

  defp nested_value(value, [key | rest]) when is_map(value) do
    case map_value(value, key) do
      nil -> nil
      next -> nested_value(next, rest)
    end
  end

  defp nested_value(_value, _keys), do: nil

  defp normalize_state(nil), do: nil
  defp normalize_state(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_state(value), do: to_string(value)

  defp list_value(map, key) do
    case map_value(map, key) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp integer_value(map, key, fallback_key \\ nil) do
    value = map_value(map, key) || (fallback_key && map_value(map, fallback_key))

    if is_integer(value), do: value, else: 0
  end

  defp integer_or_nil(value) when is_integer(value), do: value
  defp integer_or_nil(_value), do: nil

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Map.get(@atom_keys, key))
  end

  defp map_value(_map, _key), do: nil

  defp compact_map(map), do: Map.reject(map, fn {_key, value} -> value in [nil, []] end)
end

defmodule Extravaganza.Presenters.JSONSupport do
  @moduledoc false

  def normalize(%{} = map) do
    Map.new(map, fn {key, value} -> {key, normalize(value)} end)
  end

  def normalize(values) when is_list(values), do: Enum.map(values, &normalize/1)
  def normalize("nil"), do: nil
  def normalize("true"), do: true
  def normalize("false"), do: false
  def normalize(value), do: value
end

defmodule Extravaganza.Presenters.SubjectPresenter do
  @moduledoc "Shared subject-detail presenter preserving legacy browser assign keys."

  alias AppKit.Core.RuntimeReadback.{Presenter, RuntimeSubjectDetail}
  alias Extravaganza.Presenters.JSONSupport
  alias Extravaganza.Presenters.StatePresenter

  @legacy_keys %{
    actions: [],
    timeline: [],
    unified_trace: nil,
    lineage_summary: %{},
    trace_error: nil,
    read_lease: nil,
    stream_attach_lease: nil
  }

  @spec present(struct() | map(), keyword()) :: map()
  def present(value, opts \\ [])

  def present(%RuntimeSubjectDetail{} = detail, opts) do
    detail
    |> Presenter.present(opts)
    |> put_in(["schema_ref"], "headless_subject_detail.v1")
    |> update_in(["data"], &Map.merge(StatePresenter.future_m2_slots(), &1))
    |> JSONSupport.normalize()
  end

  def present(%{} = detail, opts) do
    subject = Map.get(detail, :subject) || Map.get(detail, "subject")

    assigns =
      @legacy_keys
      |> Map.merge(%{
        subject: subject,
        actions: Map.get(detail, :actions, []),
        timeline: Map.get(detail, :timeline, []),
        unified_trace: Map.get(detail, :unified_trace),
        lineage_summary: Map.get(detail, :lineage_summary, %{}),
        trace_error: Map.get(detail, :trace_error)
      })
      |> Map.merge(opts |> Enum.into(%{}) |> Map.get(:extra_assigns, %{}))

    Map.merge(assigns, %{future_m2: StatePresenter.future_m2_slots()})
  end
end

defmodule Extravaganza.Presenters.RunPresenter do
  @moduledoc "Shared run-detail presenter."

  alias AppKit.Core.RuntimeReadback.{Presenter, RuntimeRunDetail}
  alias Extravaganza.Presenters.JSONSupport
  alias Extravaganza.Presenters.StatePresenter

  @spec present(struct() | map(), keyword()) :: map()
  def present(value, opts \\ [])

  def present(%RuntimeRunDetail{} = detail, opts) do
    detail
    |> Presenter.present(opts)
    |> put_in(["schema_ref"], "headless_run_detail.v1")
    |> update_in(["data"], &Map.merge(StatePresenter.future_m2_slots(), &1))
    |> JSONSupport.normalize()
  end

  def present(%{} = detail, opts) do
    %{
      "schema_ref" => "headless_run_detail.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" => Map.merge(StatePresenter.future_m2_slots(), stringify(detail))
    }
  end

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
