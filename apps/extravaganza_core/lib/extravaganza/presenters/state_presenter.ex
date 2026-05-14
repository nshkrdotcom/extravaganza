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
  @state_readback_coverage_kinds ~w[
    running
    retrying
    completed_bookkeeping
    available_slots
    poll_state
    codex_totals
    rate_limits
    stale_reasons
    blocked_reasons
  ]
  @blocked_reason_codes ~w[
    blocked_by_non_terminal
    non_terminal_dependency
    pre_dispatch_revalidation
    source_blocked
  ]
  @atom_keys %{
    "attempt_ref" => :attempt_ref,
    "available" => :available,
    "blocked_reason" => :blocked_reason,
    "blocked_reasons" => :blocked_reasons,
    "cached_input_tokens" => :cached_input_tokens,
    "checking?" => :checking?,
    "claim_state" => :claim_state,
    "code" => :code,
    "completion_state" => :completion_state,
    "blocker_refs" => :blocker_refs,
    "diagnostics" => :diagnostics,
    "display_label" => :display_label,
    "dispatch_eligible?" => :dispatch_eligible?,
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
    "message" => :message,
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
    "reason_code" => :reason_code,
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
    "severity" => :severity,
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

    derived_orchestrator_state = symphony_orchestrator_state(data)
    data = Map.put_new(data, "symphony_orchestrator_state", derived_orchestrator_state)

    orchestrator_state =
      map_value(data, "symphony_orchestrator_state") || derived_orchestrator_state

    coverage = state_readback_coverage(data)

    data
    |> Map.put("operator_dashboard", operator_dashboard(orchestrator_state))
    |> Map.put("state_readback_coverage", coverage)
    |> Map.put("state_readback_coverage_gaps", state_readback_coverage_gaps(coverage))
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

  defp state_readback_coverage(data) do
    rows = list_value(data, "rows")
    orchestrator_state = map_value(data, "symphony_orchestrator_state") || %{}

    %{
      "running" => running_coverage(orchestrator_state),
      "retrying" => retrying_coverage(orchestrator_state),
      "completed_bookkeeping" => completed_bookkeeping_coverage(orchestrator_state),
      "available_slots" => available_slots_coverage(orchestrator_state),
      "poll_state" => poll_state_coverage(orchestrator_state),
      "codex_totals" => codex_totals_coverage(orchestrator_state),
      "rate_limits" => rate_limits_coverage(orchestrator_state),
      "stale_reasons" => stale_reasons_coverage(data, orchestrator_state),
      "blocked_reasons" => blocked_reasons_coverage(rows)
    }
    |> compact_map()
  end

  defp state_readback_coverage_gaps(coverage) do
    Enum.reject(@state_readback_coverage_kinds, fn kind ->
      coverage
      |> Map.get(kind)
      |> coverage_present?()
    end)
  end

  defp coverage_present?(%{} = coverage) do
    coverage
    |> Map.drop(["fields"])
    |> Enum.any?(fn {_key, value} -> value not in [nil, [], %{}] end)
  end

  defp coverage_present?(_coverage), do: false

  defp running_coverage(orchestrator_state) do
    running = list_value(orchestrator_state, "running")

    %{
      "fields" => [
        "symphony_orchestrator_state.running",
        "symphony_orchestrator_state.counts.running"
      ],
      "subject_refs" => string_values(running, "subject_ref"),
      "run_refs" => string_values(running, "run_ref"),
      "session_ids" => string_values(running, "session_id")
    }
    |> compact_map()
  end

  defp retrying_coverage(orchestrator_state) do
    attempts = list_value(orchestrator_state, "retry_attempts")

    %{
      "fields" => [
        "symphony_orchestrator_state.retrying",
        "symphony_orchestrator_state.retry_attempts",
        "symphony_orchestrator_state.counts.retrying"
      ],
      "attempt_refs" => string_values(attempts, "attempt_ref"),
      "reasons" => string_values(attempts, "reason")
    }
    |> compact_map()
  end

  defp completed_bookkeeping_coverage(orchestrator_state) do
    %{
      "fields" => [
        "symphony_orchestrator_state.completed",
        "symphony_orchestrator_state.counts.completed"
      ],
      "subject_refs" => list_value(orchestrator_state, "completed")
    }
    |> compact_map()
  end

  defp available_slots_coverage(orchestrator_state) do
    %{
      "fields" => ["symphony_orchestrator_state.slots"],
      "slots" => map_value(orchestrator_state, "slots")
    }
    |> compact_map()
  end

  defp poll_state_coverage(orchestrator_state) do
    %{
      "fields" => ["symphony_orchestrator_state.polling"],
      "polling" => map_value(orchestrator_state, "polling")
    }
    |> compact_map()
  end

  defp codex_totals_coverage(orchestrator_state) do
    %{
      "fields" => ["symphony_orchestrator_state.codex_totals"],
      "totals" => map_value(orchestrator_state, "codex_totals")
    }
    |> compact_map()
  end

  defp rate_limits_coverage(orchestrator_state) do
    rate_limits = list_value(orchestrator_state, "codex_rate_limits")

    %{
      "fields" => ["symphony_orchestrator_state.codex_rate_limits"],
      "limit_refs" => string_values(rate_limits, "limit_id")
    }
    |> compact_map()
  end

  defp stale_reasons_coverage(data, orchestrator_state) do
    codes =
      data
      |> list_value("diagnostics")
      |> Enum.filter(&String.contains?(to_string(map_value(&1, "code")), "stale"))
      |> string_values("code")

    warning_codes =
      orchestrator_state
      |> list_value("reconciliation_warnings")
      |> Enum.filter(&String.contains?(to_string(map_value(&1, "code")), "stale"))
      |> string_values("code")

    %{
      "fields" => [
        "diagnostics",
        "symphony_orchestrator_state.reconciliation_warnings"
      ],
      "diagnostic_codes" => Enum.uniq(codes ++ warning_codes)
    }
    |> compact_map()
  end

  defp blocked_reasons_coverage(rows) do
    blocked_reasons = Enum.flat_map(rows, &blocked_reasons_for_row/1)

    %{
      "fields" => ["rows.extensions.blocked_reason"],
      "reason_codes" => blocked_reasons |> string_values("reason_code") |> Enum.uniq(),
      "subject_refs" => blocked_reasons |> string_values("subject_ref") |> Enum.uniq()
    }
    |> compact_map()
  end

  defp blocked_reasons_for_row(row) do
    row
    |> map_value("extensions")
    |> extension_blocked_reasons()
    |> Enum.map(fn blocked_reason ->
      reason_code =
        map_value(blocked_reason, "reason_code") ||
          map_value(blocked_reason, "reason")

      %{
        "subject_ref" => map_value(row, "subject_ref"),
        "reason_code" => normalize_blocked_reason(reason_code)
      }
    end)
    |> Enum.filter(&(&1["reason_code"] in @blocked_reason_codes))
  end

  defp extension_blocked_reasons(extensions) do
    [
      nested_value(extensions, ["blocked_reason"]),
      nested_value(extensions, ["blocked_reasons"]),
      nested_value(extensions, ["dispatch_eligibility"])
    ]
    |> Enum.flat_map(fn
      values when is_list(values) -> values
      value when is_map(value) -> [value]
      _value -> []
    end)
  end

  defp normalize_blocked_reason(nil), do: nil
  defp normalize_blocked_reason("blocked_by_non_terminal"), do: "non_terminal_dependency"
  defp normalize_blocked_reason(value), do: normalize_state(value)

  defp counts(rows, data) do
    %{
      "running" => Enum.count(rows, &running?/1),
      "retrying" => length(list_value(data, "retry_rows")),
      "completed" => Enum.count(rows, &completed?/1)
    }
  end

  defp operator_dashboard(orchestrator_state) do
    codex_totals = map_value(orchestrator_state, "codex_totals") || empty_codex_totals()

    %{
      "replacement_for" => "symphony_status_dashboard",
      "counts" => map_value(orchestrator_state, "counts") || %{},
      "running" => list_value(orchestrator_state, "running"),
      "retrying" => list_value(orchestrator_state, "retrying"),
      "token_summary" => codex_totals,
      "throughput" => throughput_summary(codex_totals),
      "rate_limits" => list_value(orchestrator_state, "codex_rate_limits"),
      "polling" => map_value(orchestrator_state, "polling") || %{},
      "surface_links" => %{
        "events" => "/api/v1/events",
        "logs" => "/api/v1/logs",
        "queue" => "/queue",
        "state" => "/api/v1/state",
        "status" => "/api/v1/status"
      }
    }
  end

  defp throughput_summary(codex_totals) do
    seconds_running = integer_value(codex_totals, "seconds_running")
    total_tokens = integer_value(codex_totals, "total_tokens")

    tokens_per_second =
      if seconds_running > 0 do
        total_tokens / seconds_running
      else
        0.0
      end

    %{
      "source" => "codex_totals.seconds_running",
      "tokens_per_second" => tokens_per_second
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

  defp string_values(values, key) when is_list(values) do
    values
    |> Enum.map(&map_value(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
  end

  defp integer_value(map, key, fallback_key \\ nil) do
    value = map_value(map, key) || (fallback_key && map_value(map, fallback_key))

    if is_integer(value), do: value, else: 0
  end

  defp integer_or_nil(value) when is_integer(value), do: value
  defp integer_or_nil(_value), do: nil

  defp map_value(map, key) when is_map(map) do
    atom_key = Map.get(@atom_keys, key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      atom_key && Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> nil
    end
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
  @subject_readback_coverage_kinds ~w[
    issue_identifier_lookup
    normalized_issue_fields
    runtime_projection
    available_actions
    read_leases
    source_refs
    active_run_refs
    blockers
  ]
  @normalized_issue_fields ~w[
    identifier
    title
    description
    priority
    labels
    source_state
    source_url
    branch_ref
  ]
  @atom_keys %{
    "action" => :action,
    "action_kind" => :action_kind,
    "allowed_operations" => :allowed_operations,
    "available_actions" => :available_actions,
    "blocker_ref" => :blocker_ref,
    "blocker_refs" => :blocker_refs,
    "blocking_conditions" => :blocking_conditions,
    "branch_ref" => :branch_ref,
    "description" => :description,
    "events" => :events,
    "execution_ref" => :execution_ref,
    "identifier" => :identifier,
    "issue_identifier" => :issue_identifier,
    "labels" => :labels,
    "operation" => :operation,
    "priority" => :priority,
    "provider_refs" => :provider_refs,
    "read_lease" => :read_lease,
    "read_leases" => :read_leases,
    "reason" => :reason,
    "reason_code" => :reason_code,
    "run_ref" => :run_ref,
    "runs" => :runs,
    "source" => :source,
    "source_binding_id" => :source_binding_id,
    "source_ref" => :source_ref,
    "source_state" => :source_state,
    "source_url" => :source_url,
    "state" => :state,
    "stream_attach_lease" => :stream_attach_lease,
    "subject_ref" => :subject_ref,
    "summary" => :summary,
    "title" => :title
  }

  @spec present(struct() | map(), keyword()) :: map()
  def present(value, opts \\ [])

  def present(%RuntimeSubjectDetail{} = detail, opts) do
    detail
    |> Presenter.present(opts)
    |> put_in(["schema_ref"], "headless_subject_detail.v1")
    |> update_in(["data"], &with_subject_readback/1)
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

  defp with_subject_readback(data) when is_map(data) do
    data = Map.merge(StatePresenter.future_m2_slots(), data)
    coverage = subject_readback_coverage(data)

    data
    |> Map.put("subject_readback_coverage", coverage)
    |> Map.put("subject_readback_coverage_gaps", subject_readback_coverage_gaps(coverage))
  end

  defp subject_readback_coverage(data) do
    summary = map_value(data, "summary") || %{}
    source = map_value(summary, "source") || %{}
    runtime_row = map_value(data, "runtime_row") || %{}

    %{
      "issue_identifier_lookup" => issue_identifier_lookup_coverage(data, summary, source),
      "normalized_issue_fields" => normalized_issue_fields_coverage(summary, source),
      "runtime_projection" => runtime_projection_coverage(runtime_row, data),
      "available_actions" => available_actions_coverage(summary),
      "read_leases" => read_leases_coverage(summary),
      "source_refs" => source_refs_coverage(summary, source),
      "active_run_refs" => active_run_refs_coverage(runtime_row, data),
      "blockers" => blockers_coverage(summary, source)
    }
    |> compact_map()
  end

  defp subject_readback_coverage_gaps(coverage) do
    Enum.reject(@subject_readback_coverage_kinds, fn kind ->
      coverage
      |> Map.get(kind)
      |> coverage_present?()
    end)
  end

  defp issue_identifier_lookup_coverage(_data, summary, source) do
    %{
      "fields" => ["subject_ref", "summary.issue_identifier"],
      "issue_identifier" =>
        map_value(summary, "issue_identifier") ||
          map_value(source, "identifier") ||
          map_value(source, "source_id")
    }
    |> compact_map()
  end

  defp normalized_issue_fields_coverage(summary, source) do
    %{
      "fields" => ["summary", "summary.source"],
      "field_names" =>
        Enum.filter(
          @normalized_issue_fields,
          &normalized_issue_field_present?(&1, summary, source)
        )
    }
    |> compact_map()
  end

  defp runtime_projection_coverage(runtime_row, _data) do
    %{
      "fields" => ["runtime_row", "events"],
      "subject_refs" => runtime_row |> singleton_string_value("subject_ref"),
      "execution_refs" => runtime_row |> singleton_string_value("execution_ref"),
      "states" => runtime_row |> singleton_string_value("state")
    }
    |> compact_map()
  end

  defp available_actions_coverage(summary) do
    %{
      "fields" => ["summary.available_actions"],
      "action_kinds" =>
        summary
        |> list_value("available_actions")
        |> Enum.map(&(map_value(&1, "action_kind") || map_value(&1, "action")))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&to_string/1)
    }
    |> compact_map()
  end

  defp read_leases_coverage(summary) do
    read_leases = map_value(summary, "read_leases") || %{}

    %{
      "fields" => ["summary.read_leases"],
      "operations" =>
        [
          read_leases |> map_value("read_lease") |> map_value("operation"),
          read_leases |> map_value("stream_attach_lease") |> map_value("operation")
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&to_string/1)
    }
    |> compact_map()
  end

  defp source_refs_coverage(summary, source) do
    %{
      "fields" => ["summary.provider_refs", "summary.source"],
      "provider_refs" => summary |> map_value("provider_refs") |> map_values(),
      "source_binding_ids" => source |> singleton_string_value("source_binding_id"),
      "source_refs" => source |> singleton_string_value("source_ref")
    }
    |> compact_map()
  end

  defp active_run_refs_coverage(runtime_row, data) do
    run_refs =
      runtime_row
      |> singleton_string_value("run_ref")
      |> Kernel.++(data |> list_value("runs") |> string_values("run_ref"))
      |> Enum.uniq()

    %{
      "fields" => ["runtime_row.run_ref", "runs"],
      "run_refs" => run_refs
    }
    |> compact_map()
  end

  defp blockers_coverage(summary, source) do
    blockers = list_value(summary, "blocking_conditions") ++ list_value(source, "blocker_refs")

    %{
      "fields" => ["summary.blocking_conditions", "summary.source.blocker_refs"],
      "reason_codes" =>
        blockers
        |> Enum.map(&(map_value(&1, "reason_code") || map_value(&1, "reason")))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&to_string/1)
        |> Enum.uniq(),
      "blocker_refs" =>
        blockers
        |> Enum.flat_map(&blocker_refs/1)
        |> Enum.uniq()
    }
    |> compact_map()
  end

  defp normalized_issue_field_present?("title", summary, source),
    do: present?(map_value(summary, "title") || map_value(source, "title"))

  defp normalized_issue_field_present?("identifier", summary, source),
    do:
      present?(
        map_value(summary, "issue_identifier") ||
          map_value(source, "identifier") ||
          map_value(source, "source_id")
      )

  defp normalized_issue_field_present?(field, _summary, source),
    do: present?(map_value(source, field))

  defp blocker_refs(blocker) do
    direct_refs =
      [
        map_value(blocker, "blocker_ref"),
        map_value(blocker, "subject_ref")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    direct_refs ++ list_value(blocker, "blocker_refs")
  end

  defp map_values(map) when is_map(map) do
    map
    |> Map.values()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
  end

  defp map_values(_value), do: []

  defp singleton_string_value(map, key) do
    case map_value(map, key) do
      nil -> []
      value -> [to_string(value)]
    end
  end

  defp string_values(values, key) when is_list(values) do
    values
    |> Enum.map(&map_value(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
  end

  defp list_value(map, key) do
    case map_value(map, key) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp coverage_present?(%{} = coverage) do
    coverage
    |> Map.drop(["fields"])
    |> Enum.any?(fn {_key, value} -> value not in [nil, [], %{}] end)
  end

  defp coverage_present?(_coverage), do: false

  defp present?(value), do: value not in [nil, "", [], %{}]

  defp map_value(map, key) when is_map(map) do
    atom_key = Map.get(@atom_keys, key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      atom_key && Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> nil
    end
  end

  defp map_value(_map, _key), do: nil

  defp compact_map(map), do: Map.reject(map, fn {_key, value} -> value in [nil, []] end)
end

defmodule Extravaganza.Presenters.RunPresenter do
  @moduledoc "Shared run-detail presenter."

  alias AppKit.Core.RuntimeReadback.{Presenter, RuntimeRunDetail}
  alias Extravaganza.Presenters.JSONSupport
  alias Extravaganza.Presenters.StatePresenter

  @run_readback_coverage_kinds ~w[
    lower_run_handle
    workspace_identity
    prompt_profile_refs
    turn_limits
    current_status
    retry_metadata
    continuation_decision
    last_codex_event
    receipts
  ]
  @atom_keys %{
    "acceptance" => :acceptance,
    "acceptance_receipt_ref" => :acceptance_receipt_ref,
    "attempt_ref" => :attempt_ref,
    "continuation" => :continuation,
    "continuation?" => :continuation?,
    "continuation_prompt_ref" => :continuation_prompt_ref,
    "continuation_turn_count" => :continuation_turn_count,
    "decision" => :decision,
    "delay_ms" => :delay_ms,
    "delay_type" => :delay_type,
    "display_label" => :display_label,
    "event_kind" => :event_kind,
    "event_ref" => :event_ref,
    "event_seq" => :event_seq,
    "execution_ref" => :execution_ref,
    "extensions" => :extensions,
    "governance" => :governance,
    "id" => :id,
    "lower_envelope" => :lower_envelope,
    "lower_receipt" => :lower_receipt,
    "lower_receipt_ref" => :lower_receipt_ref,
    "lower_request_ref" => :lower_request_ref,
    "max_turns" => :max_turns,
    "max_turns_reached?" => :max_turns_reached?,
    "message_summary" => :message_summary,
    "next_delay_ms" => :next_delay_ms,
    "path_redacted?" => :path_redacted?,
    "profile_ref" => :profile_ref,
    "prompt_profile" => :prompt_profile,
    "prompt_ref" => :prompt_ref,
    "reason" => :reason,
    "retry_receipt_ref" => :retry_receipt_ref,
    "retry_receipts" => :retry_receipts,
    "retry_ref" => :retry_ref,
    "review_decision" => :review_decision,
    "run_ref" => :run_ref,
    "runtime_profile_ref" => :runtime_profile_ref,
    "runtime_row" => :runtime_row,
    "sandbox_profile_ref" => :sandbox_profile_ref,
    "session_ref" => :session_ref,
    "source_contract_ref" => :source_contract_ref,
    "source_publication" => :source_publication,
    "source_publication_receipt_ref" => :source_publication_receipt_ref,
    "state" => :state,
    "status" => :status,
    "status_reason" => :status_reason,
    "token_totals" => :token_totals,
    "total_input_tokens" => :total_input_tokens,
    "total_output_tokens" => :total_output_tokens,
    "total_tokens" => :total_tokens,
    "turn_count" => :turn_count,
    "turns" => :turns,
    "updated_at" => :updated_at,
    "workflow_ref" => :workflow_ref,
    "workspace_ref" => :workspace_ref
  }

  @spec present(struct() | map(), keyword()) :: map()
  def present(value, opts \\ [])

  def present(%RuntimeRunDetail{} = detail, opts) do
    detail
    |> Presenter.present(opts)
    |> put_in(["schema_ref"], "headless_run_detail.v1")
    |> update_in(["data"], &with_run_readback/1)
    |> JSONSupport.normalize()
  end

  def present(%{} = detail, opts) do
    data =
      detail
      |> stringify()
      |> with_run_readback()

    %{
      "schema_ref" => "headless_run_detail.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" => data
    }
  end

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp with_run_readback(data) when is_map(data) do
    data = Map.merge(StatePresenter.future_m2_slots(), data)
    coverage = run_readback_coverage(data)

    data
    |> Map.put("run_readback_coverage", coverage)
    |> Map.put("run_readback_coverage_gaps", run_readback_coverage_gaps(coverage))
  end

  defp run_readback_coverage(data) do
    runtime_row = map_value(data, "runtime_row") || %{}
    extensions = map_value(runtime_row, "extensions") || %{}
    events = list_value(data, "events")
    retries = list_value(data, "retries")
    turns = list_value(data, "turns")

    %{
      "lower_run_handle" => lower_run_handle_coverage(data, runtime_row, extensions, turns),
      "workspace_identity" => workspace_identity_coverage(runtime_row),
      "prompt_profile_refs" => prompt_profile_refs_coverage(extensions, events, turns),
      "turn_limits" => turn_limits_coverage(extensions, turns),
      "current_status" => current_status_coverage(runtime_row),
      "retry_metadata" => retry_metadata_coverage(retries),
      "continuation_decision" => continuation_decision_coverage(extensions, retries),
      "last_codex_event" => last_codex_event_coverage(runtime_row, events),
      "receipts" => receipts_coverage(extensions)
    }
    |> compact_map()
  end

  defp run_readback_coverage_gaps(coverage) do
    Enum.reject(@run_readback_coverage_kinds, fn kind ->
      coverage
      |> Map.get(kind)
      |> coverage_present?()
    end)
  end

  defp lower_run_handle_coverage(data, runtime_row, extensions, turns) do
    lower_envelope = map_value(extensions, "lower_envelope") || %{}
    lower_receipt = map_value(extensions, "lower_receipt") || %{}

    %{
      "fields" => [
        "run_ref",
        "runtime_row.run_ref",
        "runtime_row.execution_ref",
        "runtime_row.workflow_ref",
        "runtime_row.session_ref",
        "runtime_row.extensions.lower_envelope",
        "runtime_row.extensions.lower_receipt"
      ],
      "run_refs" =>
        string_values([map_value(data, "run_ref"), map_value(runtime_row, "run_ref")]),
      "execution_refs" => singleton_string_value(runtime_row, "execution_ref"),
      "workflow_refs" => singleton_string_value(runtime_row, "workflow_ref"),
      "session_refs" => session_refs(runtime_row),
      "lower_request_refs" =>
        string_values([map_value(lower_envelope, "lower_request_ref")]) ++
          string_values(turns, "lower_request_ref"),
      "lower_receipt_refs" =>
        string_values([map_value(lower_receipt, "lower_receipt_ref")]) ++
          string_values(turns, "lower_receipt_ref")
    }
    |> uniq_lists()
    |> compact_map()
  end

  defp workspace_identity_coverage(runtime_row) do
    workspace_ref = map_value(runtime_row, "workspace_ref") || %{}

    %{
      "fields" => ["runtime_row.workspace_ref"],
      "workspace_refs" => singleton_string_value(workspace_ref, "id"),
      "display_labels" => singleton_string_value(workspace_ref, "display_label"),
      "path_redacted?" => map_value(workspace_ref, "path_redacted?")
    }
    |> compact_map()
  end

  defp prompt_profile_refs_coverage(extensions, events, turns) do
    governance = map_value(extensions, "governance") || %{}
    lower_envelope = map_value(extensions, "lower_envelope") || %{}
    prompt_profile = map_value(extensions, "prompt_profile") || %{}

    %{
      "fields" => [
        "runtime_row.extensions.governance",
        "runtime_row.extensions.lower_envelope",
        "runtime_row.extensions.prompt_profile",
        "events.profile_ref",
        "events.source_contract_ref",
        "turns"
      ],
      "prompt_refs" =>
        string_values([map_value(prompt_profile, "prompt_ref")]) ++
          string_values(turns, "prompt_ref"),
      "continuation_prompt_refs" =>
        string_values([map_value(prompt_profile, "continuation_prompt_ref")]) ++
          string_values(turns, "continuation_prompt_ref"),
      "profile_refs" =>
        string_values([
          map_value(governance, "runtime_profile_ref"),
          map_value(prompt_profile, "profile_ref")
        ]) ++
          string_values(events, "profile_ref") ++ string_values(turns, "profile_ref"),
      "sandbox_profile_refs" =>
        string_values([map_value(lower_envelope, "sandbox_profile_ref")]) ++
          string_values(turns, "sandbox_profile_ref"),
      "source_contract_refs" =>
        string_values([map_value(prompt_profile, "source_contract_ref")]) ++
          string_values(events, "source_contract_ref") ++
          string_values(turns, "source_contract_ref")
    }
    |> uniq_lists()
    |> compact_map()
  end

  defp turn_limits_coverage(extensions, turns) do
    continuation = map_value(extensions, "continuation") || %{}

    %{
      "fields" => ["turns", "runtime_row.extensions.continuation"],
      "turn_counts" =>
        integer_values([map_value(continuation, "turn_count")]) ++
          integer_values(turns, "turn_count"),
      "max_turns" =>
        integer_values([map_value(continuation, "max_turns")]) ++
          integer_values(turns, "max_turns"),
      "continuation_turn_counts" =>
        integer_values([map_value(continuation, "continuation_turn_count")]) ++
          integer_values(turns, "continuation_turn_count"),
      "max_turns_reached?" =>
        first_boolean([
          map_value(continuation, "max_turns_reached?")
          | Enum.map(turns, &map_value(&1, "max_turns_reached?"))
        ])
    }
    |> uniq_lists()
    |> compact_map()
  end

  defp current_status_coverage(runtime_row) do
    %{
      "fields" => [
        "runtime_row.state",
        "runtime_row.status_reason",
        "runtime_row.updated_at"
      ],
      "states" => singleton_string_value(runtime_row, "state"),
      "status_reasons" => singleton_string_value(runtime_row, "status_reason"),
      "updated_at" => singleton_string_value(runtime_row, "updated_at")
    }
    |> compact_map()
  end

  defp retry_metadata_coverage(retries) do
    %{
      "fields" => ["retries"],
      "retry_refs" => string_values(retries, "retry_ref"),
      "attempt_refs" => string_values(retries, "attempt_ref"),
      "continuation_attempt_refs" =>
        retries
        |> Enum.filter(&(map_value(&1, "continuation?") == true))
        |> string_values("attempt_ref"),
      "delay_types" => string_values(retries, "delay_type"),
      "statuses" => string_values(retries, "status")
    }
    |> uniq_lists()
    |> compact_map()
  end

  defp continuation_decision_coverage(extensions, retries) do
    continuation = map_value(extensions, "continuation") || %{}
    continuation_retries = Enum.filter(retries, &(map_value(&1, "continuation?") == true))

    %{
      "fields" => ["retries", "runtime_row.extensions.continuation"],
      "decisions" =>
        string_values([
          map_value(continuation, "decision") ||
            if(continuation_retries == [], do: nil, else: "schedule_continuation_retry")
        ]),
      "reasons" =>
        string_values([map_value(continuation, "reason")]) ++
          string_values(continuation_retries, "reason"),
      "next_delay_ms" =>
        integer_values([map_value(continuation, "next_delay_ms")]) ++
          integer_values(continuation_retries, "delay_ms")
    }
    |> uniq_lists()
    |> compact_map()
  end

  defp last_codex_event_coverage(runtime_row, events) do
    token_totals = token_totals_coverage(map_value(runtime_row, "token_totals"))

    %{
      "fields" => ["events", "runtime_row.token_totals"],
      "event_refs" => events |> last_codex_events() |> string_values("event_ref"),
      "event_kinds" => events |> last_codex_events() |> string_values("event_kind"),
      "session_refs" => events |> last_codex_events() |> string_values("session_ref"),
      "message_summaries" => events |> last_codex_events() |> string_values("message_summary"),
      "token_totals" => if(token_totals == %{}, do: [], else: [token_totals])
    }
    |> compact_map()
  end

  defp receipts_coverage(extensions) do
    lower_receipt = map_value(extensions, "lower_receipt") || %{}
    source_publication = map_value(extensions, "source_publication") || %{}
    review_decision = map_value(extensions, "review_decision") || %{}
    acceptance = map_value(extensions, "acceptance") || %{}

    %{
      "fields" => [
        "runtime_row.extensions.lower_receipt",
        "runtime_row.extensions.retry_receipts",
        "runtime_row.extensions.source_publication",
        "runtime_row.extensions.review_decision",
        "runtime_row.extensions.acceptance"
      ],
      "lower_receipt_refs" => singleton_string_value(lower_receipt, "lower_receipt_ref"),
      "retry_receipt_refs" =>
        extensions
        |> list_value("retry_receipts")
        |> string_values("retry_receipt_ref"),
      "source_publication_receipt_refs" =>
        singleton_string_value(source_publication, "source_publication_receipt_ref"),
      "review_decision_refs" => singleton_string_value(review_decision, "decision_ref"),
      "acceptance_receipt_refs" => singleton_string_value(acceptance, "acceptance_receipt_ref")
    }
    |> compact_map()
  end

  defp session_refs(runtime_row) do
    case map_value(runtime_row, "session_ref") do
      %{} = session_ref -> singleton_string_value(session_ref, "id")
      value when is_binary(value) -> [value]
      _other -> []
    end
  end

  defp last_codex_events(events) do
    events
    |> Enum.filter(fn event ->
      event
      |> map_value("event_kind")
      |> to_string()
      |> String.starts_with?("codex.")
    end)
    |> Enum.sort_by(&(map_value(&1, "event_seq") || -1), :desc)
    |> Enum.take(1)
  end

  defp token_totals_coverage(nil), do: %{}

  defp token_totals_coverage(%{} = token_totals) do
    %{
      "input_tokens" => map_value(token_totals, "total_input_tokens"),
      "output_tokens" => map_value(token_totals, "total_output_tokens"),
      "total_tokens" => map_value(token_totals, "total_tokens")
    }
    |> compact_map()
  end

  defp token_totals_coverage(_value), do: %{}

  defp first_boolean(values) do
    case Enum.find(values, &(is_boolean(&1) or &1 in ["true", "false"])) do
      value when is_boolean(value) -> value
      "true" -> true
      "false" -> false
      _other -> nil
    end
  end

  defp singleton_string_value(map, key) do
    case map_value(map, key) do
      nil -> []
      value -> [to_string(value)]
    end
  end

  defp string_values(values, key) when is_list(values) do
    values
    |> Enum.map(&map_value(&1, key))
    |> string_values()
  end

  defp string_values(values) when is_list(values) do
    values
    |> Enum.reject(&(&1 in [nil, "nil"]))
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  defp integer_values(values, key) when is_list(values) do
    values
    |> Enum.map(&map_value(&1, key))
    |> integer_values()
  end

  defp integer_values(values) when is_list(values) do
    values
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
  end

  defp list_value(map, key) do
    case map_value(map, key) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp coverage_present?(%{} = coverage) do
    coverage
    |> Map.drop(["fields"])
    |> Enum.any?(fn {_key, value} -> value not in [nil, [], %{}] end)
  end

  defp coverage_present?(_coverage), do: false

  defp map_value(map, key) when is_map(map) do
    atom_key = Map.get(@atom_keys, key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      atom_key && Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> nil
    end
  end

  defp map_value(_map, _key), do: nil

  defp uniq_lists(map) do
    Map.new(map, fn
      {key, value} when is_list(value) -> {key, Enum.uniq(value)}
      entry -> entry
    end)
  end

  defp compact_map(map), do: Map.reject(map, fn {_key, value} -> value in [nil, []] end)
end
