defmodule ExtravaganzaWeb.Api.HeadlessControllerTest do
  use ExtravaganzaWeb.ConnCase, async: false

  alias Extravaganza.{ProductBootstrap, ProductHost, ProductPack}
  alias Extravaganza.TestSupport.{ExecutionTraceFixture, FakeHeadlessBackend}
  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.Pack.Compiler

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

    assert body["ok"] == true
    assert body["schema"] == "extravaganza.headless.response.v1"
    assert body["operation"] == "state"
    assert body["data"]["schema_ref"] == "headless_state_snapshot.v1"

    assert body["data"]["data"]["page"] == %{
             "page_size" => 25,
             "cursor" => nil,
             "total_entries" => 9
           }

    assert Enum.any?(body["data"]["data"]["rows"], &(&1["state"] == "running"))
    assert body["data"]["data"]["turns"] == []

    encoded = Jason.encode!(body)
    refute String.contains?(encoded, "workspace_path")
    refute String.contains?(encoded, "/home/")
  end

  test "GET /api/v1/subjects/:subject_id and compatibility issue route share subject presenter",
       %{
         conn: conn
       } do
    subject = get(conn, ~p"/api/v1/subjects/subject:fixture") |> json_response(200)
    issue = get(conn, ~p"/api/v1/ENG-42") |> json_response(200)

    assert subject["operation"] == "subject"
    assert issue["operation"] == "subject"
    assert subject["data"]["schema_ref"] == "headless_subject_detail.v1"
    assert issue["data"]["schema_ref"] == "headless_subject_detail.v1"
    assert subject["data"]["data"]["agent_loop_diagnostics"] == []

    assert Enum.any?(
             subject["data"]["data"]["events"],
             &(&1["event_kind"] == "future_m2_state_added")
           )
  end

  test "GET /api/v1/runs/:run_id returns ordered events and M2-safe slots", %{conn: conn} do
    body = get(conn, ~p"/api/v1/runs/run:fixture") |> json_response(200)

    assert body["operation"] == "run"
    assert body["data"]["schema_ref"] == "headless_run_detail.v1"

    assert Enum.map(body["data"]["data"]["events"], & &1["event_ref"]) == [
             "event:run:1",
             "event:run:2"
           ]

    assert body["data"]["data"]["candidate_fact_refs"] == []
    assert body["data"]["data"]["memory_proof_refs"] == []
  end

  test "POST refresh and control return command result envelopes", %{conn: conn} do
    refresh =
      post(conn, ~p"/api/v1/refresh", %{"idempotency_key" => "idem:api-refresh"})
      |> json_response(202)

    assert refresh["operation"] == "refresh"
    assert refresh["data"]["schema_ref"] == "headless_command_result.v1"
    assert refresh["data"]["data"]["command_kind"] == "refresh"
    assert refresh["data"]["data"]["workflow_effect_state"] == "pending_signal"

    accepted =
      post(conn, ~p"/api/v1/subjects/subject:fixture/control/retry", %{
        "idempotency_key" => "idem:api-retry"
      })
      |> json_response(202)

    assert accepted["operation"] == "control"
    assert accepted["data"]["data"]["accepted?"] == true
    assert accepted["data"]["data"]["workflow_effect_state"] == "pending_signal"

    denied =
      post(conn, ~p"/api/v1/subjects/subject:fixture/actions/cancel", %{
        "idempotency_key" => "idem:api-cancel",
        "deny" => "true"
      })
      |> json_response(200)

    assert denied["operation"] == "control"
    assert denied["data"]["data"]["accepted?"] == false
    assert denied["data"]["data"]["workflow_effect_state"] == "rejected_by_authority"
  end

  test "POST review decision returns the shared command result presenter", %{conn: conn} do
    reviews = get(conn, ~p"/api/v1/reviews") |> json_response(200)

    assert reviews["operation"] == "reviews"
    assert reviews["data"]["schema_ref"] == "headless_reviews.v1"

    body =
      conn
      |> recycle()
      |> post(~p"/api/v1/reviews/decision:fixture/decisions/accept", %{
        "decision_kind" => "operator_review",
        "subject_id" => "subject:fixture",
        "subject_kind" => "linear_issue",
        "reason" => "accepted from API contract test"
      })
      |> json_response(202)

    assert body["operation"] == "review"
    assert body["data"]["schema_ref"] == "headless_command_result.v1"
    assert body["data"]["data"]["command_kind"] == "review_decision"
    assert body["data"]["data"]["workflow_effect_state"] == "pending_signal"
  end

  test "GET evidence and events use the same standard envelope", %{conn: conn} do
    evidence = get(conn, ~p"/api/v1/runs/run:fixture/evidence") |> json_response(200)
    events = get(conn, ~p"/api/v1/events?run_id=run:fixture") |> json_response(200)

    assert evidence["operation"] == "evidence"
    assert evidence["data"]["schema_ref"] == "headless_evidence_chain.v1"
    assert evidence["refs"]["authority_ref"] == "authority:fixture"

    assert events["operation"] == "events"
    assert events["data"]["schema_ref"] == "headless_events.v1"

    assert Enum.map(events["data"]["data"]["entries"], & &1["event_ref"]) == [
             "event:run:1",
             "event:run:2"
           ]
  end

  test "GET source publication preview uses the shared source presenter", %{conn: conn} do
    body =
      get(conn, ~p"/api/v1/subjects/subject:fixture/source-publication")
      |> json_response(200)

    assert body["operation"] == "source_publication"
    assert body["data"]["schema_ref"] == "headless_source_publication.v1"

    assert body["data"]["data"]["source_publication_receipt_ref"] ==
             "source-publication:fixture"

    assert body["refs"]["source_publication_ref"] == "source-publication:fixture"
  end

  test "POST read and stream attach leases return shared lease envelopes", %{
    conn: conn,
    tenant_id: tenant_id,
    pack_version: pack_version
  } do
    subject_id = start_subject_with_trace!(tenant_id: tenant_id, pack_version: pack_version)

    read =
      post(conn, ~p"/api/v1/subjects/#{subject_id}/read-lease", %{})
      |> json_response(200)

    assert read["operation"] == "read_lease"
    assert read["data"]["schema_ref"] == "headless_lease.v1"
    assert get_in(read, ["data", "data", "lease_ref", "execution_ref", "id"])

    stream =
      conn
      |> recycle()
      |> post(~p"/api/v1/subjects/#{subject_id}/stream-attach-lease", %{})
      |> json_response(200)

    assert stream["operation"] == "stream_attach_lease"
    assert stream["data"]["schema_ref"] == "headless_lease.v1"
    assert is_integer(get_in(stream, ["data", "data", "reconnect_cursor"]))
  end

  test "API routes return JSON method-not-allowed and not-found envelopes", %{conn: conn} do
    method_not_allowed = put(conn, ~p"/api/v1/state", %{}) |> json_response(405)
    assert method_not_allowed["ok"] == false
    assert method_not_allowed["error"]["code"] == "method_not_allowed"

    not_found =
      conn
      |> recycle()
      |> get("/api/v1/not/a/defined/route")
      |> json_response(404)

    assert not_found["ok"] == false
    assert not_found["error"]["code"] == "not_found"
  end

  test "known API error classes use stable statuses and shared error envelopes", %{conn: conn} do
    bad_request = get(conn, ~p"/api/v1/events") |> json_response(400)
    assert bad_request["error"]["code"] == "bad_request"
    assert bad_request["error"]["class"] == "invalid_request"

    invalid_action =
      conn
      |> recycle()
      |> post(~p"/api/v1/subjects/subject:fixture/control/not-a-real-action", %{})
      |> json_response(422)

    assert invalid_action["error"]["code"] == "invalid_action"

    action_denied =
      conn
      |> recycle()
      |> with_backend(__MODULE__.ActionDeniedBackend, fn conn ->
        post(conn, ~p"/api/v1/subjects/subject:fixture/control/cancel", %{})
      end)
      |> json_response(403)

    assert action_denied["error"]["code"] == "action_denied"

    projection_unavailable =
      conn
      |> recycle()
      |> with_backend(__MODULE__.ProjectionUnavailableBackend, fn conn ->
        get(conn, ~p"/api/v1/runs/run:fixture")
      end)
      |> json_response(404)

    assert projection_unavailable["error"]["code"] == "projection_unavailable"
    assert projection_unavailable["error"]["class"] == "readback_unavailable"

    timeout =
      conn
      |> recycle()
      |> with_backend(__MODULE__.TimeoutBackend, fn conn -> get(conn, ~p"/api/v1/state") end)
      |> json_response(503)

    assert timeout["error"]["code"] == "snapshot_timeout"
    assert timeout["error"]["class"] == "timeout"
    assert timeout["error"]["retryable"] == true
  end

  test "standard JSON error envelope maps unavailable states", %{conn: conn} do
    body =
      with_backend(conn, __MODULE__.UnavailableBackend, fn conn ->
        get(conn, ~p"/api/v1/state")
      end)
      |> json_response(503)

    assert body["ok"] == false
    assert body["schema"] == "extravaganza.headless.error.v1"
    assert body["error"]["code"] == "unavailable"
    assert is_binary(body["trace_id"])
  end

  defp with_backend(conn, backend, callback) when is_function(callback, 1) do
    previous_backend = Application.get_env(:app_kit_core, :headless_backend)
    Application.put_env(:app_kit_core, :headless_backend, backend)

    try do
      callback.(conn)
    after
      if previous_backend do
        Application.put_env(:app_kit_core, :headless_backend, previous_backend)
      else
        Application.delete_env(:app_kit_core, :headless_backend)
      end
    end
  end

  defp start_subject_with_trace!(opts) do
    activate_fixture_registration!(opts)

    assert {:ok, result} =
             ProductHost.start_run(
               %{
                 external_ref: "linear:ENG-API-LEASE",
                 title: "Issue API lease",
                 description: "Drive API read and stream lease routes",
                 source_kind: "linear",
                 payload: %{"issue_id" => "ENG-API-LEASE"},
                 normalized_payload: %{"issue_id" => "ENG-API-LEASE"}
               },
               opts
             )

    installation_id = bootstrapped_installation_id!(opts)

    ExecutionTraceFixture.seed_execution_trace!(
      Keyword.merge(opts,
        installation_id: installation_id,
        subject_id: result.payload.work_object_id
      )
    )

    result.payload.work_object_id
  end

  defp activate_fixture_registration!(opts) do
    pack_slug = ProductPack.pack_slug(opts)
    pack_version = ProductPack.pack_version(opts)

    case PackRegistration.by_slug_version(pack_slug, pack_version) do
      {:ok, %PackRegistration{status: :active}} ->
        :ok

      {:ok, %PackRegistration{} = registration} ->
        activate_registration!(registration)

      {:error, _reason} ->
        {:ok, compiled_pack} =
          opts
          |> ProductPack.manifest()
          |> Compiler.compile()

        registration = MezzanineConfigRegistry.register_pack!(compiled_pack)
        activate_registration!(registration)
    end
  end

  defp activate_registration!(%PackRegistration{} = registration) do
    deprecate_active_subject_kind_overlaps!(registration)
    assert {:ok, %PackRegistration{status: :active}} = PackRegistration.activate(registration)
  end

  defp deprecate_active_subject_kind_overlaps!(%PackRegistration{} = registration) do
    subject_kinds = MapSet.new(registration.canonical_subject_kinds)
    assert {:ok, active_registrations} = PackRegistration.list_active()

    active_registrations
    |> Enum.reject(&(&1.id == registration.id))
    |> Enum.filter(fn active_registration ->
      active_subject_kinds = MapSet.new(active_registration.canonical_subject_kinds)
      not MapSet.disjoint?(subject_kinds, active_subject_kinds)
    end)
    |> Enum.each(fn active_registration ->
      assert {:ok, %PackRegistration{status: :deprecated}} =
               PackRegistration.deprecate(active_registration)
    end)
  end

  defp bootstrapped_installation_id!(opts) do
    assert {:ok, profile} = ProductBootstrap.ensure_bootstrapped(opts)
    profile.installation_ref.id
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

  defmodule TimeoutBackend do
    @behaviour AppKit.Core.Backends.HeadlessBackend

    def state_snapshot(_context, _request, _opts), do: {:error, :snapshot_timeout}

    def runtime_subject_detail(_context, _subject_ref, _request, _opts),
      do: {:error, :snapshot_timeout}

    def runtime_run_detail(_context, _run_ref, _request, _opts), do: {:error, :snapshot_timeout}
    def request_runtime_refresh(_context, _request, _opts), do: {:error, :snapshot_timeout}
    def request_runtime_control(_context, _request, _opts), do: {:error, :snapshot_timeout}
  end

  defmodule ProjectionUnavailableBackend do
    @behaviour AppKit.Core.Backends.HeadlessBackend

    def state_snapshot(_context, _request, _opts), do: {:error, :unavailable}

    def runtime_subject_detail(_context, _subject_ref, _request, _opts),
      do: {:error, :runtime_projection_not_found}

    def runtime_run_detail(_context, _run_ref, _request, _opts),
      do: {:error, :runtime_projection_not_found}

    def request_runtime_refresh(_context, _request, _opts), do: {:error, :unavailable}
    def request_runtime_control(_context, _request, _opts), do: {:error, :unavailable}
  end

  defmodule ActionDeniedBackend do
    @behaviour AppKit.Core.Backends.HeadlessBackend

    def state_snapshot(_context, _request, _opts), do: {:error, :unavailable}

    def runtime_subject_detail(_context, _subject_ref, _request, _opts),
      do: {:error, :unavailable}

    def runtime_run_detail(_context, _run_ref, _request, _opts), do: {:error, :unavailable}
    def request_runtime_refresh(_context, _request, _opts), do: {:error, :unavailable}
    def request_runtime_control(_context, _request, _opts), do: {:error, :action_denied}
  end
end
