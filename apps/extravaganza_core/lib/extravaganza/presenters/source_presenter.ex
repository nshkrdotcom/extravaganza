defmodule Extravaganza.Presenters.SourcePresenter do
  @moduledoc "Shared source publication presenter for CLI, REST, and future UI adapters."

  @spec present_publication_preview(map() | struct(), keyword()) :: map()
  def present_publication_preview(preview, opts \\ []) do
    %{
      "schema_ref" => "headless_source_publication.v1",
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" => dump(preview)
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
