defmodule Extravaganza.Presenters.RuntimePresenter do
  @moduledoc "Shared presenter for product runtime status, logs, and profile apply readbacks."

  @spec present_status(map() | struct(), keyword()) :: map()
  def present_status(status, opts \\ []),
    do: envelope("headless_runtime_status.v1", status, opts)

  @spec present_logs(map() | struct(), keyword()) :: map()
  def present_logs(logs, opts \\ []),
    do: envelope("headless_runtime_logs.v1", logs, opts)

  @spec present_profile_apply(map() | struct()) :: map()
  def present_profile_apply(result), do: dump(result)

  defp envelope(schema_ref, data, opts) do
    %{
      "schema_ref" => schema_ref,
      "schema_version" => 1,
      "generated_at" => Keyword.get(opts, :generated_at),
      "correlation_id" => Keyword.get(opts, :correlation_id),
      "data" => dump(data)
    }
  end

  defp dump(%_{} = value), do: value |> Map.from_struct() |> dump()

  defp dump(%{} = map),
    do: Map.new(map, fn {key, value} -> {to_string(key), dump_value(value)} end)

  defp dump(values) when is_list(values), do: Enum.map(values, &dump_value/1)
  defp dump(value), do: dump_value(value)

  defp dump_value(%_{} = value), do: value |> Map.from_struct() |> dump()
  defp dump_value(%{} = value), do: dump(value)
  defp dump_value(values) when is_list(values), do: Enum.map(values, &dump_value/1)
  defp dump_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp dump_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp dump_value(%Date{} = value), do: Date.to_iso8601(value)
  defp dump_value(%Time{} = value), do: Time.to_iso8601(value)
  defp dump_value(value), do: value
end
