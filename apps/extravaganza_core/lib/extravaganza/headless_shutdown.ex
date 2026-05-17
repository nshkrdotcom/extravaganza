defmodule Extravaganza.HeadlessShutdown do
  @moduledoc """
  Product-owned graceful shutdown/offline-status readback for headless operators.
  """

  @schema_ref "headless_shutdown.v1"
  @replacement_for "symphony_application_stop_offline_status"
  @offline_status_replacement "symphony_status_dashboard_render_offline_status"
  @product_exposure [
    "mix extravaganza.headless.stop",
    "scripts/headless/stop.exs",
    "POST /api/v1/shutdown",
    "/api/v1/status",
    "/api/v1/logs"
  ]

  @type shutdown_result :: {:ok, map()} | {:error, {atom(), map()}}

  @spec run(keyword() | map()) :: shutdown_result()
  def run(opts \\ []) when is_list(opts) or is_map(opts) do
    opts = opts_map(opts)
    report = report(opts)

    case report["status"] do
      "offline" -> {:ok, report}
      "blocked_active_lower_runs" -> {:error, {:active_lower_runs_present, report}}
      "blocked_missing_lower_run_posture" -> {:error, {:lower_run_posture_required, report}}
    end
  end

  defp report(opts) do
    lower_run_posture = lower_run_posture(opts)
    status = shutdown_status(lower_run_posture)
    trace_id = trace_id(opts)

    %{
      "schema_ref" => @schema_ref,
      "replacement_for" => @replacement_for,
      "status" => status,
      "offline_status_rendered?" => status == "offline",
      "offline_status" => offline_status(status, opts, trace_id),
      "lower_run_posture" => lower_run_posture,
      "orphan_prevention" => orphan_prevention(status, lower_run_posture),
      "operator_action" => operator_action(status),
      "product_exposure" => @product_exposure,
      "generated_by" => "Extravaganza.HeadlessShutdown"
    }
    |> compact()
  end

  defp lower_run_posture(opts) do
    active_refs = active_lower_run_refs(opts)

    cond do
      active_refs != [] ->
        %{
          "status" => "active_lower_runs_present",
          "source" => "caller_supplied_refs",
          "active_lower_run_count" => length(active_refs),
          "active_lower_run_refs" => active_refs
        }

      truthy?(opt(opts, :confirm_no_active_lower_runs?, confirm_aliases())) ->
        %{
          "status" => "no_active_lower_runs",
          "source" => "operator_confirmation",
          "active_lower_run_count" => 0,
          "active_lower_run_refs" => []
        }

      true ->
        %{
          "status" => "posture_required",
          "source" => "not_supplied",
          "active_lower_run_count" => nil,
          "active_lower_run_refs" => []
        }
    end
  end

  defp shutdown_status(%{"status" => "active_lower_runs_present"}),
    do: "blocked_active_lower_runs"

  defp shutdown_status(%{"status" => "no_active_lower_runs"}), do: "offline"
  defp shutdown_status(_posture), do: "blocked_missing_lower_run_posture"

  defp offline_status("offline", opts, trace_id) do
    reason = string_opt(opts, :reason, ["reason"], "operator_shutdown")
    generated_at = generated_at(opts)

    %{
      "replacement_for" => @offline_status_replacement,
      "app_status" => "offline",
      "terminal_line" => "app_status=offline",
      "rendered_format" => "standard_json",
      "event" => %{
        "event_ref" => "event://extravaganza/shutdown/offline/#{ref_suffix(trace_id)}",
        "event_kind" => "runtime.offline",
        "trace_id" => trace_id,
        "reason" => reason,
        "app_status" => "offline",
        "occurred_at" => generated_at
      }
    }
  end

  defp offline_status(_status, _opts, _trace_id), do: nil

  defp orphan_prevention("offline", lower_run_posture) do
    %{
      "verdict" => "safe_to_stop",
      "orphaned_lower_runs?" => false,
      "proof" => "no active lower runs confirmed before offline status was rendered",
      "active_lower_run_count" => lower_run_posture["active_lower_run_count"]
    }
  end

  defp orphan_prevention("blocked_active_lower_runs", lower_run_posture) do
    %{
      "verdict" => "shutdown_blocked",
      "orphaned_lower_runs?" => false,
      "proof" => "offline status was not rendered because active lower runs were present",
      "active_lower_run_count" => lower_run_posture["active_lower_run_count"],
      "active_lower_run_refs" => lower_run_posture["active_lower_run_refs"]
    }
  end

  defp orphan_prevention(_status, _lower_run_posture) do
    %{
      "verdict" => "posture_required",
      "orphaned_lower_runs?" => false,
      "proof" => "offline status was not rendered because lower-run posture was not supplied"
    }
  end

  defp operator_action("offline") do
    %{
      "status" => "complete",
      "next" => "operator may let the headless shell exit"
    }
  end

  defp operator_action("blocked_active_lower_runs") do
    %{
      "status" => "blocked",
      "next" =>
        "cancel, complete, or wait for active lower runs through product/AppKit control surfaces"
    }
  end

  defp operator_action(_status) do
    %{
      "status" => "blocked",
      "next" => "supply --confirm-no-active-lower-runs or active lower-run refs before shutdown"
    }
  end

  defp active_lower_run_refs(opts) do
    opts
    |> list_opt(:active_lower_run_refs, [
      "active_lower_run_refs",
      "active-lower-run-refs",
      :active_lower_run_ref,
      "active_lower_run_ref",
      "active-lower-run-ref"
    ])
    |> Enum.uniq()
  end

  defp list_opt(opts, key, aliases) do
    opts
    |> opt(key, aliases)
    |> split_list()
  end

  defp split_list(nil), do: []

  defp split_list(values) when is_list(values) do
    values
    |> Enum.flat_map(&split_list/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_list(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_list(value), do: [to_string(value)]

  defp string_opt(opts, key, aliases, default) do
    case opt(opts, key, aliases) do
      value when value in [nil, ""] -> default
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end
  end

  defp trace_id(opts),
    do:
      string_opt(
        opts,
        :trace_id,
        ["trace_id", "trace-id"],
        "trace:extravaganza:shutdown:#{System.unique_integer([:positive])}"
      )

  defp generated_at(opts),
    do:
      string_opt(
        opts,
        :generated_at,
        ["generated_at", "generated-at"],
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      )

  defp ref_suffix(value) do
    value
    |> to_string()
    |> String.to_charlist()
    |> Enum.reduce({[], false}, &append_ref_suffix_char/2)
    |> elem(0)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp append_ref_suffix_char(char, {chars, in_replacement?}) do
    cond do
      ref_suffix_char?(char) ->
        {[char | chars], false}

      in_replacement? ->
        {chars, true}

      true ->
        {[?- | chars], true}
    end
  end

  defp ref_suffix_char?(char) do
    char in ?A..?Z or char in ?a..?z or char in ?0..?9 or char in [?_, ?., ?:, ?-]
  end

  defp confirm_aliases do
    [
      "confirm_no_active_lower_runs?",
      :confirm_no_active_lower_runs,
      "confirm_no_active_lower_runs",
      "confirm-no-active-lower-runs"
    ]
  end

  defp opts_map(opts) when is_map(opts), do: opts
  defp opts_map(opts) when is_list(opts), do: Map.new(opts)

  defp opt(opts, key, aliases) do
    Enum.find_value([key | aliases], fn candidate ->
      value = Map.get(opts, candidate)
      if is_nil(value), do: nil, else: value
    end)
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp compact(%{} = map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
