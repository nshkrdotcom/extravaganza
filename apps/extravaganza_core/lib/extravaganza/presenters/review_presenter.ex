defmodule Extravaganza.Presenters.ReviewPresenter do
  @moduledoc "Shared pending-review presenter."

  @spec present_page(map(), keyword()) :: map()
  def present_page(%{page: page}, opts \\ []) do
    entries = Map.get(page, :entries, [])

    %{
      "schema_ref" => "headless_reviews.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" => %{
        "entries" => Enum.map(entries, &present_review/1),
        "page" => %{
          "page_size" => length(entries),
          "cursor" => Map.get(page, :next_cursor),
          "total_entries" => Map.get(page, :total_count, length(entries))
        }
      }
    }
  end

  defp present_review(review) do
    %{
      "decision_ref" => dump_ref(Map.get(review, :decision_ref)),
      "subject_ref" => dump_ref(Map.get(review, :subject_ref)),
      "status" => Map.get(review, :status),
      "summary" => Map.get(review, :summary),
      "required_by" => timestamp(Map.get(review, :required_by))
    }
  end

  defp dump_ref(nil), do: nil
  defp dump_ref(%_{} = value), do: value |> Map.from_struct() |> stringify()
  defp dump_ref(value), do: value
  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp timestamp(value), do: value
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

  def present(%{} = result, opts) do
    %{
      "schema_ref" => "headless_command_result.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" => stringify(result)
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

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
