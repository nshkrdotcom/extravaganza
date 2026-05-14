defmodule ExtravaganzaWeb.ObservabilityUpdatesTest do
  use ExUnit.Case, async: false

  alias ExtravaganzaWeb.ObservabilityUpdates

  test "broadcast_update emits a safe Symphony dashboard replacement envelope" do
    assert :ok = ObservabilityUpdates.subscribe()

    assert :ok =
             ObservabilityUpdates.broadcast_update(:refresh_requested, %{
               "subject_ref" => "subject:fixture",
               "api_key" => "linear-api-secret",
               "workspace_path" => "/home/operator/workspace"
             })

    assert_receive {:headless_observability_updated, update}, 500

    assert update["schema_ref"] == "headless_observability_update.v1"
    assert update["reason"] == "refresh_requested"
    assert update["replacement_for"] == "symphony_observability_pubsub"
    assert update["metadata"]["subject_ref"] == "subject:fixture"
    assert update["metadata"]["api_key"] == "[REDACTED]"
    assert update["metadata"]["workspace_path"] == "[REDACTED_PATH]"
    assert "/operator-console" in update["refresh_targets"]
    assert "/api/v1/state" in update["refresh_targets"]
    assert "/api/v1/events" in update["refresh_targets"]
  end

  test "broadcast_update is a no-op when PubSub is not running" do
    assert :ok =
             ObservabilityUpdates.broadcast_update(
               :refresh_requested,
               %{"subject_ref" => "subject:fixture"},
               pubsub: :extravaganza_missing_pubsub_for_test
             )
  end
end
