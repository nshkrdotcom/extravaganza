defmodule Extravaganza.Presenters.RuntimePresenter do
  @moduledoc "Shared presenter for product runtime status, logs, and profile apply readbacks."

  @workflow_reload_missing :__workflow_reload_missing__

  @spec present_status(map() | struct(), keyword()) :: map()
  def present_status(status, opts \\ []) do
    workflow_reload = Keyword.get(opts, :workflow_reload, @workflow_reload_missing)

    envelope("headless_runtime_status.v1", put_workflow_reload(status, workflow_reload), opts)
  end

  @spec present_logs(map() | struct(), keyword()) :: map()
  def present_logs(logs, opts \\ []),
    do: envelope("headless_runtime_logs.v1", redact_log_data(logs), opts)

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

  defp put_workflow_reload(status, @workflow_reload_missing), do: status
  defp put_workflow_reload(status, nil), do: status

  defp put_workflow_reload(%_{} = status, workflow_reload) when is_map(workflow_reload) do
    metadata = Map.get(status, :metadata) || %{}
    %{status | metadata: Map.put(metadata, "workflow_reload", workflow_reload)}
  end

  defp put_workflow_reload(%{} = status, workflow_reload) when is_map(workflow_reload) do
    metadata = Map.get(status, :metadata) || Map.get(status, "metadata") || %{}
    Map.put(status, "metadata", Map.put(metadata, "workflow_reload", workflow_reload))
  end

  defp put_workflow_reload(status, _workflow_reload), do: status

  defp dump(%_{} = value), do: value |> Map.from_struct() |> dump()

  defp dump(%{} = map),
    do: Map.new(map, fn {key, value} -> {to_string(key), dump_value(value)} end)

  defp dump(values) when is_list(values), do: Enum.map(values, &dump_value/1)
  defp dump(value), do: dump_value(value)

  defp dump_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp dump_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp dump_value(%Date{} = value), do: Date.to_iso8601(value)
  defp dump_value(%Time{} = value), do: Time.to_iso8601(value)
  defp dump_value(%_{} = value), do: value |> Map.from_struct() |> dump()
  defp dump_value(%{} = value), do: dump(value)
  defp dump_value(values) when is_list(values), do: Enum.map(values, &dump_value/1)
  defp dump_value(value), do: value

  defp redact_log_data(%_{} = value), do: value |> Map.from_struct() |> redact_log_data()

  defp redact_log_data(%{} = map) do
    Map.new(map, fn {key, value} ->
      key = to_string(key)
      {key, redact_log_value(key, value)}
    end)
  end

  defp redact_log_data(values) when is_list(values),
    do: Enum.map(values, &redact_log_value(nil, &1))

  defp redact_log_data(value), do: redact_log_value(nil, value)

  defp redact_log_value(key, value) when is_binary(value) do
    cond do
      sensitive_log_key?(key) -> "[redacted]"
      Path.type(value) == :absolute -> "[redacted-path]"
      true -> value
    end
  end

  defp redact_log_value(_key, %DateTime{} = value), do: value
  defp redact_log_value(_key, %NaiveDateTime{} = value), do: value
  defp redact_log_value(_key, %Date{} = value), do: value
  defp redact_log_value(_key, %Time{} = value), do: value
  defp redact_log_value(_key, %_{} = value), do: value |> Map.from_struct() |> redact_log_data()
  defp redact_log_value(_key, %{} = value), do: redact_log_data(value)

  defp redact_log_value(_key, values) when is_list(values),
    do: Enum.map(values, &redact_log_value(nil, &1))

  defp redact_log_value(_key, value), do: value

  defp sensitive_log_key?(nil), do: false

  defp sensitive_log_key?(key) do
    normalized =
      key
      |> to_string()
      |> String.downcase()

    Enum.any?(
      [
        "api_key",
        "apikey",
        "authorization",
        "credential",
        "password",
        "private_key",
        "secret",
        "token"
      ],
      &String.contains?(normalized, &1)
    )
  end
end
