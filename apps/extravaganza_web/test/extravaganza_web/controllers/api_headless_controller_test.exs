defmodule ExtravaganzaWeb.Api.HeadlessControllerTest do
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

  test "GET /api/v1/state returns the offline M1 state presenter", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/state")
    body = json_response(conn, 200)

    assert body["schema_ref"] == "headless_state_snapshot.v1"
    assert body["data"]["page"] == %{"page_size" => 25, "cursor" => nil, "total_entries" => 9}
    assert Enum.any?(body["data"]["rows"], &(&1["state"] == "running"))
    assert body["data"]["turns"] == []

    encoded = Jason.encode!(body)
    refute encoded =~ "workspace_path"
    refute encoded =~ "/home/"
  end

  test "GET /api/v1/subjects/:subject_id and compatibility issue route share subject presenter",
       %{
         conn: conn
       } do
    subject = get(conn, ~p"/api/v1/subjects/subject:fixture") |> json_response(200)
    issue = get(conn, ~p"/api/v1/ENG-42") |> json_response(200)

    assert subject["schema_ref"] == "headless_subject_detail.v1"
    assert issue["schema_ref"] == "headless_subject_detail.v1"
    assert subject["data"]["agent_loop_diagnostics"] == []
    assert Enum.any?(subject["data"]["events"], &(&1["event_kind"] == "future_m2_state_added"))
  end

  test "GET /api/v1/runs/:run_id returns ordered events and M2-safe slots", %{conn: conn} do
    body = get(conn, ~p"/api/v1/runs/run:fixture") |> json_response(200)

    assert body["schema_ref"] == "headless_run_detail.v1"
    assert Enum.map(body["data"]["events"], & &1["event_ref"]) == ["event:run:1", "event:run:2"]
    assert body["data"]["candidate_fact_refs"] == []
    assert body["data"]["memory_proof_refs"] == []
  end

  test "POST refresh and control return command result envelopes", %{conn: conn} do
    refresh =
      post(conn, ~p"/api/v1/refresh", %{"idempotency_key" => "idem:api-refresh"})
      |> json_response(200)

    assert refresh["schema_ref"] == "headless_command_result.v1"
    assert refresh["data"]["command_kind"] == "refresh"
    assert refresh["data"]["workflow_effect_state"] == "pending_signal"

    denied =
      post(conn, ~p"/api/v1/subjects/subject:fixture/actions/cancel", %{
        "idempotency_key" => "idem:api-cancel",
        "deny" => "true"
      })
      |> json_response(200)

    assert denied["data"]["accepted?"] == false
    assert denied["data"]["workflow_effect_state"] == "rejected_by_authority"
  end

  test "standard JSON error envelope maps unavailable states", %{conn: conn} do
    previous_backend = Application.get_env(:app_kit_core, :headless_backend)
    Application.put_env(:app_kit_core, :headless_backend, __MODULE__.UnavailableBackend)

    on_exit(fn -> Application.put_env(:app_kit_core, :headless_backend, previous_backend) end)

    body = get(conn, ~p"/api/v1/state") |> json_response(503)

    assert body["error"]["code"] == "unavailable"
    assert is_binary(body["error"]["correlation_id"])
  end

  defmodule UnavailableBackend do
    @behaviour AppKit.Core.Backends.HeadlessBackend

    def state_snapshot(_context, _request, _opts), do: {:error, :unavailable}

    def runtime_subject_detail(_context, _subject_ref, _request, _opts),
      do: {:error, :unavailable}

    def runtime_run_detail(_context, _run_ref, _request, _opts), do: {:error, :unavailable}
    def request_runtime_refresh(_context, _request, _opts), do: {:error, :unavailable}
    def request_runtime_control(_context, _request, _opts), do: {:error, :unavailable}
  end
end
