defmodule ExtravaganzaWeb.Api.HeadlessRunReadbackControllerTest do
  use ExtravaganzaWeb.ConnCase, async: false

  alias Extravaganza.TestSupport.FakeHeadlessBackend
  alias ExtravaganzaWeb.HeadlessSurfaceOptions

  setup %{conn: conn} do
    {:ok, conn: HeadlessSurfaceOptions.put(conn, headless_backend: FakeHeadlessBackend)}
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

    data = body["data"]["data"]

    assert data["runtime_row"]["extensions"]["provider_request_response"]["provider"] == "linear"

    assert data["runtime_row"]["extensions"]["provider_request_response"]["operation"] ==
             "linear.comments.create"

    assert data["runtime_row"]["extensions"]["source_publication"]["comment_ref"] ==
             "linear-comment:fixture"

    assert [turn] = data["turns"]
    assert turn["provider_session_id"] == "thread-1"
    assert turn["provider_turn_id"] == "turn-1"
    refute Map.has_key?(turn, "codex_session_id")

    encoded = Jason.encode!(body)
    refute String.contains?(encoded, "linear_comment_id")
    refute String.contains?(encoded, "codex_session_id")
    refute String.contains?(encoded, "workspace_path")
    refute String.contains?(encoded, "/tmp/")
    refute String.contains?(encoded, "/home/")
    refute String.contains?(encoded, "api_key")
  end
end
