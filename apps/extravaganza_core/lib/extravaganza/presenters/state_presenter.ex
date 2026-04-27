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
    entries = Map.get(page, :entries, [])

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

  defp with_future_slots(data) when is_map(data), do: Map.merge(@future_m2_slots, data)
  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
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
