defmodule ExtravaganzaWeb.Api.HeadlessRunReadbackControllerTest do
  use ExtravaganzaWeb.ConnCase, async: false

  alias Extravaganza.TestSupport.FakeHeadlessBackend

  setup do
    previous_backend = Application.get_env(:app_kit_core, :headless_backend)
    previous_fixture_context = Application.get_env(:extravaganza_core, :headless_fixture_context?)

    Application.put_env(:app_kit_core, :headless_backend, FakeHeadlessBackend)
    Application.put_env(:extravaganza_core, :headless_fixture_context?, true)

    on_exit(fn ->
      if previous_backend do
        Application.put_env(:app_kit_core, :headless_backend, previous_backend)
      else
        Application.delete_env(:app_kit_core, :headless_backend)
      end

      if is_nil(previous_fixture_context) do
        Application.delete_env(:extravaganza_core, :headless_fixture_context?)
      else
        Application.put_env(
          :extravaganza_core,
          :headless_fixture_context?,
          previous_fixture_context
        )
      end
    end)
  end

  test "GET /api/v1/runs/:run_id exposes run readback coverage through product route", %{
    conn: conn
  } do
    body = get(conn, ~p"/api/v1/runs/run:fixture") |> json_response(200)

    assert body["operation"] == "run"
    assert body["data"]["schema_ref"] == "headless_run_detail.v1"
    assert body["data"]["data"]["run_readback_coverage_gaps"] == []

    coverage = body["data"]["data"]["run_readback_coverage"]

    assert coverage["lower_run_handle"]["run_refs"] == ["run:fixture"]
    assert coverage["workspace_identity"]["workspace_refs"] == ["workspace:fixture"]
    assert coverage["workspace_identity"]["path_redacted?"] == true
    assert coverage["prompt_profile_refs"]["prompt_refs"] == ["prompt:fixture:first"]
    assert coverage["turn_limits"]["turn_counts"] == [2]
    assert coverage["turn_limits"]["max_turns"] == [3]
    assert coverage["current_status"]["states"] == ["stalled"]
    assert coverage["retry_metadata"]["continuation_attempt_refs"] == ["attempt:fixture:1"]
    assert coverage["continuation_decision"]["decisions"] == ["schedule_continuation_retry"]
    assert coverage["last_codex_event"]["event_kinds"] == ["codex.agent_message.updated"]
    assert coverage["receipts"]["lower_receipt_refs"] == ["lower-receipt:fixture"]

    encoded = Jason.encode!(body)
    refute String.contains?(encoded, "workspace_path")
    refute String.contains?(encoded, "/tmp/")
    refute String.contains?(encoded, "/home/")
    refute String.contains?(encoded, "api_key")
  end
end
