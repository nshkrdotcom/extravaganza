defmodule ExtravaganzaWeb.ObservabilityUpdates do
  @moduledoc """
  Product-owned observability update fanout for the operator console.

  This is the Extravaganza web-shell replacement for Symphony's dashboard
  PubSub topic. It carries only product DTO/update metadata and does not read
  lower stores, provider SDKs, or ambient OS environment variables.
  """

  @pubsub ExtravaganzaWeb.PubSub
  @topic "headless:observability"
  @message_tag :headless_observability_updated
  @replacement_for "symphony_observability_pubsub"
  @schema_ref "headless_observability_update.v1"
  @refresh_targets [
    "/operator-console",
    "/api/v1/state",
    "/api/v1/status",
    "/api/v1/events",
    "/api/v1/logs"
  ]
  @known_reasons ~w[
    refresh_requested
    source_sync
    run_status_change
    review_decision
    live_provider_receipt
  ]
  @secret_fragments ~w[
    api_key
    authorization
    credential
    password
    private_key
    raw_secret
    raw_token
    secret
    token
  ]
  @path_fragments ~w[
    local_path
    logs_root
    path
    workspace
    workspace_path
  ]

  @spec subscribe(keyword()) :: :ok | {:error, term()}
  def subscribe(opts \\ []) when is_list(opts) do
    opts
    |> pubsub_name()
    |> Phoenix.PubSub.subscribe(@topic)
  end

  @spec broadcast_update(atom() | String.t(), map(), keyword()) :: :ok
  def broadcast_update(reason, metadata \\ %{}, opts \\ [])
      when is_map(metadata) and is_list(opts) do
    pubsub = pubsub_name(opts)

    if Process.whereis(pubsub) do
      Phoenix.PubSub.broadcast(pubsub, @topic, {@message_tag, update_payload(reason, metadata)})
    end

    :ok
  end

  @spec update_payload(atom() | String.t(), map()) :: map()
  def update_payload(reason, metadata \\ %{}) when is_map(metadata) do
    reason = normalize_reason(reason)

    %{
      "schema_ref" => @schema_ref,
      "schema_version" => 1,
      "replacement_for" => @replacement_for,
      "topic" => @topic,
      "message" => "headless_observability_updated",
      "reason" => reason,
      "known_reason?" => reason in @known_reasons,
      "refresh_targets" => @refresh_targets,
      "metadata" => sanitize_metadata(metadata),
      "generated_at" => timestamp()
    }
  end

  @spec ready_payload() :: map()
  def ready_payload do
    %{
      "schema_ref" => @schema_ref,
      "schema_version" => 1,
      "replacement_for" => @replacement_for,
      "topic" => @topic,
      "message" => "headless_observability_ready",
      "reason" => "stream_ready",
      "refresh_targets" => @refresh_targets,
      "generated_at" => timestamp()
    }
  end

  @spec keepalive_payload() :: map()
  def keepalive_payload do
    %{
      "schema_ref" => @schema_ref,
      "schema_version" => 1,
      "replacement_for" => @replacement_for,
      "topic" => @topic,
      "message" => "headless_observability_keepalive",
      "reason" => "stream_keepalive",
      "generated_at" => timestamp()
    }
  end

  @spec encode_sse(String.t(), map()) :: String.t()
  def encode_sse(event, payload) when is_binary(event) and is_map(payload) do
    "event: " <> event <> "\n" <> "data: " <> Jason.encode!(payload) <> "\n\n"
  end

  defp sanitize_metadata(metadata) do
    metadata
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} ->
      string_key = to_string(key)
      {string_key, sanitize_value(string_key, value)}
    end)
  end

  defp sanitize_value(key, value) when is_map(value) do
    if secret_key?(key), do: "[REDACTED]", else: sanitize_metadata(value)
  end

  defp sanitize_value(key, values) when is_list(values) do
    if secret_key?(key), do: "[REDACTED]", else: Enum.map(values, &sanitize_nested_value/1)
  end

  defp sanitize_value(key, value) when is_binary(value) do
    cond do
      secret_key?(key) -> "[REDACTED]"
      path_key?(key) or unsafe_path?(value) -> "[REDACTED_PATH]"
      true -> value
    end
  end

  defp sanitize_value(key, value) do
    if secret_key?(key), do: "[REDACTED]", else: value
  end

  defp sanitize_nested_value(%{} = value), do: sanitize_metadata(value)

  defp sanitize_nested_value(values) when is_list(values),
    do: Enum.map(values, &sanitize_nested_value/1)

  defp sanitize_nested_value(value) when is_binary(value) do
    if unsafe_path?(value), do: "[REDACTED_PATH]", else: value
  end

  defp sanitize_nested_value(value), do: value

  defp secret_key?(key) do
    key = String.downcase(to_string(key))
    Enum.any?(@secret_fragments, &String.contains?(key, &1))
  end

  defp path_key?(key) do
    key = String.downcase(to_string(key))
    Enum.any?(@path_fragments, &String.contains?(key, &1))
  end

  defp unsafe_path?(value) do
    Path.type(value) == :absolute and not String.starts_with?(value, @refresh_targets)
  rescue
    ArgumentError -> false
  end

  defp normalize_reason(reason), do: reason |> to_string() |> String.replace("-", "_")
  defp pubsub_name(opts), do: Keyword.get(opts, :pubsub, @pubsub)
  defp timestamp, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
