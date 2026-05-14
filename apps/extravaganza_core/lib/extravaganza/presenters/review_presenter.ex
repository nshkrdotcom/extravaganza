defmodule Extravaganza.Presenters.ReviewPresenter do
  @moduledoc "Shared pending-review presenter."

  @review_readback_coverage_kinds ~w[
    pending_queue
    decision_identity
    gate_policy
    workflow_effects
    appkit_review_surface
  ]

  @spec present_page(map(), keyword()) :: map()
  def present_page(%{page: page}, opts \\ []) do
    entries = page_entries(page)
    presented_entries = Enum.map(entries, &present_review/1)

    data = %{
      "entries" => presented_entries,
      "page" => %{
        "page_size" => length(entries),
        "cursor" => map_value(page, :next_cursor),
        "total_entries" => map_value(page, :total_count) || length(entries)
      }
    }

    coverage = review_readback_coverage(data)

    %{
      "schema_ref" => "headless_reviews.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" =>
        data
        |> Map.put("review_readback_coverage", coverage)
        |> Map.put("review_readback_coverage_gaps", review_readback_coverage_gaps(coverage))
    }
  end

  defp present_review(review) do
    review = dump_value(review)
    decision_ref = map_value(review, :decision_ref)
    subject_ref = map_value(review, :subject_ref) || map_value(decision_ref || %{}, :subject_ref)

    %{
      "decision_ref" => dump_ref(decision_ref),
      "subject_ref" => dump_ref(subject_ref),
      "status" => scalar_string(map_value(review, :status)),
      "summary" => map_value(review, :summary),
      "required_by" => timestamp(map_value(review, :required_by)),
      "schema_ref" => map_value(review, :schema_ref),
      "schema_version" => map_value(review, :schema_version),
      "payload" => map_value(review, :payload) || %{}
    }
    |> compact_map()
  end

  defp review_readback_coverage(%{"entries" => entries, "page" => page}) do
    %{
      "pending_queue" => pending_queue_coverage(entries, page),
      "decision_identity" => decision_identity_coverage(entries),
      "gate_policy" => gate_policy_coverage(entries),
      "workflow_effects" => workflow_effects_coverage(entries),
      "appkit_review_surface" => appkit_review_surface_coverage(entries)
    }
    |> compact_map()
  end

  defp review_readback_coverage_gaps(coverage) do
    Enum.reject(@review_readback_coverage_kinds, fn kind ->
      coverage
      |> Map.get(kind)
      |> coverage_present?()
    end)
  end

  defp pending_queue_coverage(entries, page) do
    %{
      "fields" => ["page.total_entries", "page.cursor", "entries.status"],
      "total_entries" => map_value(page, :total_entries) || length(entries),
      "statuses" => entries |> values_at(:status) |> unique_strings()
    }
    |> compact_map()
  end

  defp decision_identity_coverage(entries) do
    decision_refs = Enum.map(entries, &map_value(map_value(&1, :decision_ref) || %{}, :id))
    subject_refs = Enum.map(entries, &map_value(map_value(&1, :subject_ref) || %{}, :id))

    %{
      "fields" => ["entries.decision_ref", "entries.subject_ref"],
      "decision_refs" => unique_strings(decision_refs),
      "decision_kinds" =>
        entries
        |> Enum.map(&map_value(map_value(&1, :decision_ref) || %{}, :decision_kind))
        |> unique_strings(),
      "subject_refs" => unique_strings(subject_refs)
    }
    |> compact_map()
  end

  defp gate_policy_coverage(entries) do
    quorum_profiles =
      Enum.map(entries, &map_value(map_value(&1, :payload) || %{}, :quorum_profile))

    %{
      "fields" => [
        "entries.payload.review_kind",
        "entries.decision_ref.decision_kind",
        "entries.payload.quorum_profile"
      ],
      "review_kinds" =>
        entries
        |> Enum.map(fn entry ->
          payload = map_value(entry, :payload) || %{}
          decision_ref = map_value(entry, :decision_ref) || %{}
          map_value(payload, :review_kind) || map_value(decision_ref, :decision_kind)
        end)
        |> unique_strings(),
      "quorum_modes" =>
        quorum_profiles
        |> Enum.map(&map_value(&1 || %{}, :quorum_mode))
        |> unique_strings(),
      "required_decision_counts" =>
        quorum_profiles
        |> Enum.map(&map_value(&1 || %{}, :required_decision_count))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }
    |> compact_map()
  end

  defp workflow_effects_coverage(entries) do
    %{
      "fields" => ["entries.payload.workflow_effects"],
      "effects" =>
        entries
        |> Enum.map(&map_value(map_value(&1, :payload) || %{}, :workflow_effects))
        |> normalize_workflow_effects()
    }
    |> compact_map()
  end

  defp appkit_review_surface_coverage(entries) do
    surfaces =
      entries
      |> Enum.flat_map(fn entry ->
        payload = map_value(entry, :payload) || %{}
        list_value(map_value(payload, :appkit_surfaces))
      end)
      |> unique_strings()

    %{
      "fields" => [
        "AppKit.ReviewSurface",
        "AppKit.Core.DecisionSummary",
        "entries.payload.appkit_surfaces"
      ],
      "surfaces" => surfaces
    }
    |> compact_map()
  end

  defp normalize_workflow_effects(values) do
    values
    |> Enum.reduce(%{}, fn
      %{} = effects, acc ->
        Enum.reduce(effects, acc, fn {action, effect}, action_acc ->
          Map.update(
            action_acc,
            to_string(action),
            effect |> list_value() |> unique_strings(),
            &unique_strings(&1 ++ list_value(effect))
          )
        end)

      _other, acc ->
        acc
    end)
    |> Map.reject(fn {_action, effects} -> effects == [] end)
  end

  defp page_entries(page), do: list_value(map_value(page, :entries))

  defp dump_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp dump_value(nil), do: nil
  defp dump_value(%_{} = value), do: value |> Map.from_struct() |> dump_value()

  defp dump_value(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), dump_value(value)} end)
  end

  defp dump_value(values) when is_list(values), do: Enum.map(values, &dump_value/1)
  defp dump_value(value) when is_atom(value), do: Atom.to_string(value)
  defp dump_value(value), do: value

  defp dump_ref(nil), do: nil
  defp dump_ref(%_{} = value), do: value |> Map.from_struct() |> dump_ref()
  defp dump_ref(%{} = value), do: dump_value(value)
  defp dump_ref(value), do: value

  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp timestamp(value), do: value

  defp scalar_string(nil), do: nil
  defp scalar_string(value) when is_atom(value), do: Atom.to_string(value)
  defp scalar_string(value), do: value

  defp values_at(entries, key), do: Enum.map(entries, &map_value(&1, key))

  defp map_value(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, Atom.to_string(key)) || Map.get(map, key)

  defp map_value(map, key) when is_map(map), do: Map.get(map, key)
  defp map_value(_map, _key), do: nil

  defp list_value(nil), do: []
  defp list_value(values) when is_list(values), do: values
  defp list_value(value), do: [value]

  defp unique_strings(values) do
    values
    |> List.wrap()
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp coverage_present?(%{} = coverage) do
    coverage
    |> Map.drop(["fields"])
    |> Enum.any?(fn {_key, value} -> present_value?(value) end)
  end

  defp coverage_present?(_coverage), do: false

  defp present_value?(%{} = value),
    do: Enum.any?(value, fn {_key, nested} -> present_value?(nested) end)

  defp present_value?(values) when is_list(values), do: Enum.any?(values, &present_value?/1)
  defp present_value?(nil), do: false
  defp present_value?(""), do: false
  defp present_value?(_value), do: true

  defp compact_map(map), do: Map.reject(map, fn {_key, value} -> value in [nil, []] end)
end

defmodule Extravaganza.Presenters.LeasePresenter do
  @moduledoc "Shared read/stream lease presenter."

  @spec present(struct() | map(), keyword()) :: map()
  def present(lease, opts \\ []) do
    %{
      "schema_ref" => "headless_lease.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" => dump(lease)
    }
  end

  defp dump(%_{} = value), do: value |> Map.from_struct() |> dump()

  defp dump(%{} = map),
    do: Map.new(map, fn {key, value} -> {to_string(key), dump_value(value)} end)

  defp dump(value), do: value

  defp dump_value(%_{} = value), do: value |> Map.from_struct() |> dump()
  defp dump_value(%{} = value), do: dump(value)
  defp dump_value(values) when is_list(values), do: Enum.map(values, &dump_value/1)
  defp dump_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp dump_value(value), do: value
end

defmodule Extravaganza.Presenters.CommandResultPresenter do
  @moduledoc "Shared command-result presenter."

  alias AppKit.Core.ActionResult
  alias AppKit.Core.RuntimeReadback.{CommandResult, Presenter}
  alias Extravaganza.Presenters.JSONSupport

  @spec present(struct() | map(), keyword()) :: map()
  def present(value, opts \\ [])

  def present(%CommandResult{} = result, opts) do
    result
    |> Presenter.present(opts)
    |> put_in(["schema_ref"], "headless_command_result.v1")
    |> JSONSupport.normalize()
  end

  def present(%ActionResult{} = result, opts) do
    metadata = dump_value(result.metadata || %{})
    action_ref = dump_value(result.action_ref)
    action_kind = map_value(action_ref || %{}, "action_kind")

    %{
      "schema_ref" => "headless_command_result.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" =>
        %{
          "command_ref" => map_value(action_ref || %{}, "id"),
          "command_kind" => command_kind(action_kind),
          "action_kind" => action_kind,
          "accepted?" => result.status in [:accepted, :completed],
          "coalesced?" => false,
          "status" => to_string(result.status),
          "workflow_effect_state" => workflow_effect_state(metadata),
          "projection_state" => map_value(metadata, "projection_state"),
          "trace_id" => map_value(metadata, "trace_id"),
          "correlation_id" =>
            map_value(metadata, "correlation_id") || Keyword.get(opts, :correlation_id),
          "receipt_ref" => map_value(metadata, "receipt_ref"),
          "idempotency_key" => map_value(metadata, "idempotency_key"),
          "message" => result.message,
          "authority_refs" => list_value(map_value(metadata, "authority_refs")),
          "action_ref" => action_ref,
          "execution_ref" => dump_value(result.execution_ref),
          "metadata" => metadata
        }
        |> compact_map()
    }
  end

  def present(%{} = result, opts) do
    %{
      "schema_ref" => "headless_command_result.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" => dump_value(result)
    }
  end

  def error(code, message, opts \\ []) do
    %{
      "error" => %{
        "code" => to_string(code),
        "message" => message,
        "correlation_id" => Keyword.get(opts, :correlation_id)
      }
    }
  end

  defp command_kind("review_" <> _decision), do: "review_decision"
  defp command_kind(action_kind), do: action_kind

  defp workflow_effect_state(metadata) do
    map_value(metadata, "workflow_effect_state") ||
      metadata
      |> map_value("workflow_control_effect")
      |> case do
        %{} = effect -> map_value(effect, "workflow_effect_state")
        _other -> nil
      end
  end

  defp dump_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp dump_value(nil), do: nil
  defp dump_value(%_{} = value), do: value |> Map.from_struct() |> dump_value()

  defp dump_value(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), dump_value(value)} end)
  end

  defp dump_value(values) when is_list(values), do: Enum.map(values, &dump_value/1)
  defp dump_value(value) when is_atom(value), do: Atom.to_string(value)
  defp dump_value(value), do: value

  defp map_value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp map_value(_map, _key), do: nil

  defp list_value(nil), do: []
  defp list_value(values) when is_list(values), do: values
  defp list_value(value), do: [value]

  defp compact_map(map), do: Map.reject(map, fn {_key, value} -> value in [nil, []] end)
end
