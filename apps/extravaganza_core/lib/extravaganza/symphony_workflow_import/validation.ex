defmodule Extravaganza.SymphonyWorkflowImport.Validation do
  @moduledoc false

  @spec validate_profile(map()) :: :ok | {:error, term()}
  def validate_profile(profile) when is_map(profile) do
    config = Map.get(profile, "config", %{})
    tracker = Map.get(config, "tracker", %{})
    codex = Map.get(config, "codex", %{})

    cond do
      is_nil(tracker["kind"]) ->
        {:error, :missing_tracker_kind}

      tracker["kind"] not in ["linear", "memory"] ->
        {:error, {:unsupported_tracker_kind, tracker["kind"]}}

      tracker["kind"] == "linear" and tracker["api_key_supplied?"] != true ->
        {:error, :missing_linear_api_token}

      tracker["kind"] == "linear" and blank?(tracker["project_slug"]) ->
        {:error, :missing_linear_project_slug}

      blank?(codex["command"]) ->
        {:error, :missing_codex_command}

      true ->
        :ok
    end
  end

  @spec validation_summary(map()) :: map()
  def validation_summary(config) when is_map(config) do
    case validate_profile(%{"config" => config}) do
      :ok -> %{"status" => "valid"}
      {:error, reason} -> %{"status" => "invalid", "reason" => sanitize_reason(reason)}
    end
  end

  @spec sanitize_reason(term()) :: map() | String.t()
  def sanitize_reason({reason, value}),
    do: %{"code" => to_string(reason), "value" => printable_reason_value(value)}

  def sanitize_reason({:missing_workflow_file, path, raw_reason}) do
    %{
      "code" => "missing_workflow_file",
      "value" => printable_reason_value(path),
      "reason" => printable_reason_value(raw_reason)
    }
  end

  def sanitize_reason(reason) when is_atom(reason) or is_binary(reason), do: to_string(reason)
  def sanitize_reason(reason), do: inspect(reason)

  @spec sanitize_reload_reason(term()) :: map() | String.t()
  def sanitize_reload_reason({:missing_workflow_file, path, raw_reason}) do
    %{
      "code" => "missing_workflow_file",
      "value" => redact_path(path),
      "reason" => printable_reason_value(raw_reason)
    }
  end

  def sanitize_reload_reason(reason), do: sanitize_reason(reason)

  defp printable_reason_value(value) when is_binary(value), do: value
  defp printable_reason_value(value), do: inspect(value)

  defp redact_path(path) when is_binary(path) do
    if Path.type(path) == :absolute, do: "[redacted-path]", else: path
  end

  defp blank?(value), do: is_nil(value) or value == ""
end
