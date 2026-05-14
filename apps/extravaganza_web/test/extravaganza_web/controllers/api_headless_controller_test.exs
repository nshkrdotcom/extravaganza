defmodule ExtravaganzaWeb.Api.HeadlessControllerTest do
  use ExtravaganzaWeb.ConnCase, async: false

  alias AppKit.Core.RuntimeSurface.{
    RuntimeLogPage,
    RuntimeProfileApplyResult,
    RuntimeStatusSnapshot
  }

  alias Extravaganza.{ProductBootstrap, ProductHost, ProductPack}
  alias Extravaganza.TestSupport.{ExecutionTraceFixture, FakeHeadlessBackend}
  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.Pack.Compiler

  @secret "linear-api-secret"

  setup do
    previous_backend = Application.get_env(:app_kit_core, :headless_backend)
    previous_runtime_backend = Application.get_env(:app_kit_core, :runtime_backend)
    previous_source_backend = Application.get_env(:app_kit_core, :source_backend)
    previous_fixture_context = Application.get_env(:extravaganza_core, :headless_fixture_context?)
    Application.put_env(:app_kit_core, :headless_backend, FakeHeadlessBackend)
    Application.put_env(:app_kit_core, :runtime_backend, __MODULE__.RuntimeBackend)
    Application.put_env(:app_kit_core, :source_backend, __MODULE__.SourceBackend)
    Application.put_env(:extravaganza_core, :headless_fixture_context?, true)

    on_exit(fn ->
      if previous_backend do
        Application.put_env(:app_kit_core, :headless_backend, previous_backend)
      else
        Application.delete_env(:app_kit_core, :headless_backend)
      end

      if previous_runtime_backend do
        Application.put_env(:app_kit_core, :runtime_backend, previous_runtime_backend)
      else
        Application.delete_env(:app_kit_core, :runtime_backend)
      end

      if previous_source_backend do
        Application.put_env(:app_kit_core, :source_backend, previous_source_backend)
      else
        Application.delete_env(:app_kit_core, :source_backend)
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

    orchestrator_state = body["data"]["data"]["symphony_orchestrator_state"]
    assert orchestrator_state["counts"] == %{"running" => 1, "retrying" => 2, "completed" => 1}

    [running | _rest] = orchestrator_state["running"]
    assert running["session_id"] == "session:running"
    assert running["turn_count"] == 7

    assert running["tokens"] == %{
             "input_tokens" => 120,
             "output_tokens" => 45,
             "total_tokens" => 165
           }

    assert orchestrator_state["source_sync"]["status"] == "fresh"
    assert hd(orchestrator_state["reconciliation_warnings"])["code"] == "source_state_stale"

    assert Enum.map(orchestrator_state["retrying"], & &1["attempt"]) == [
             "attempt:retrying:2",
             "attempt:retrying:3"
           ]

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
    assert subject["data"]["data"]["subject_readback_coverage_gaps"] == []
    assert issue["data"]["data"]["subject_ref"] == "ENG-42"
    assert issue["data"]["data"]["summary"]["issue_identifier"] == "ENG-42"
    assert issue["data"]["data"]["subject_readback_coverage_gaps"] == []

    assert Enum.any?(
             subject["data"]["data"]["events"],
             &(&1["event_kind"] == "future_m2_state_added")
           )

    coverage = subject["data"]["data"]["subject_readback_coverage"]

    assert coverage["available_actions"]["action_kinds"] == [
             "pause",
             "resume",
             "cancel",
             "retry",
             "rework"
           ]

    assert coverage["read_leases"]["operations"] == ["read_lease", "stream_attach_lease"]
    assert coverage["source_refs"]["source_refs"] == ["linear://fixture/issue/ENG-42"]
    assert coverage["blockers"]["reason_codes"] == ["non_terminal_dependency"]
  end

  test "GET /api/v1/runs/:run_id returns ordered events and M2-safe slots", %{conn: conn} do
    body = get(conn, ~p"/api/v1/runs/run:fixture") |> json_response(200)

    assert body["operation"] == "run"
    assert body["data"]["schema_ref"] == "headless_run_detail.v1"
    assert body["data"]["data"]["runtime_row"]["state"] == "stalled"
    assert body["data"]["data"]["runtime_row"]["status_reason"] == "stall_timeout"
    assert body["data"]["data"]["runtime_row"]["extensions"]["stall"]["elapsed_ms"] == 330_000

    assert Enum.map(body["data"]["data"]["events"], & &1["event_ref"]) ==
             Enum.map(0..15, &"event:run:#{&1}")

    hook_event =
      Enum.find(
        body["data"]["data"]["events"],
        &(&1["event_kind"] == "workspace.hook.after_create")
      )

    assert hook_event["extensions"]["hook_receipt"]["stage"] == "after_create"
    assert hook_event["extensions"]["hook_receipt"]["path_redacted?"] == true
    refute Jason.encode!(hook_event) =~ "workspace_path"
    refute Jason.encode!(hook_event) =~ "/tmp/"

    assert Enum.any?(
             body["data"]["data"]["events"],
             &(&1["event_kind"] == "retry.stale_token_ignored")
           )

    assert Enum.any?(
             body["data"]["data"]["events"],
             &(&1["event_kind"] == "cancel.terminal_source")
           )

    assert Enum.any?(
             body["data"]["data"]["events"],
             &(&1["event_kind"] == "runtime.stalled")
           )

    assert Enum.any?(
             body["data"]["data"]["retries"],
             &(&1["reason"] == "stall_timeout" and &1["status"] == "scheduled")
           )

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

    for action <- ~w[pause resume cancel retry] do
      accepted =
        conn
        |> recycle()
        |> post(~p"/api/v1/subjects/subject:fixture/control/#{action}", %{
          "idempotency_key" => "idem:api-#{action}"
        })
        |> json_response(202)

      assert accepted["operation"] == "control"
      assert accepted["data"]["data"]["command_kind"] == action
      assert accepted["data"]["data"]["accepted?"] == true
      assert accepted["data"]["data"]["idempotency_key"] == "idem:api-#{action}"
      assert accepted["data"]["data"]["workflow_effect_state"] == "pending_signal"
    end

    denied =
      conn
      |> recycle()
      |> post(~p"/api/v1/subjects/subject:fixture/actions/cancel", %{
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
    assert reviews["data"]["data"]["review_readback_coverage_gaps"] == []

    review_coverage = reviews["data"]["data"]["review_readback_coverage"]
    assert review_coverage["pending_queue"]["total_entries"] == 1
    assert review_coverage["decision_identity"]["decision_refs"] == ["decision:fixture"]
    assert review_coverage["gate_policy"]["review_kinds"] == ["operator_review"]

    assert review_coverage["workflow_effects"]["effects"] == %{
             "accept" => ["continue_lower_workflow"],
             "escalate" => ["pause_lower_workflow"],
             "reject" => ["request_rework"],
             "waive" => ["continue_lower_workflow"]
           }

    assert review_coverage["appkit_review_surface"]["surfaces"] == ["AppKit.ReviewSurface"]

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

    assert Enum.map(events["data"]["data"]["entries"], & &1["event_ref"]) ==
             Enum.map(0..15, &"event:run:#{&1}")

    assert events["data"]["data"]["timeline_coverage_gaps"] == []

    assert Enum.any?(
             events["data"]["data"]["entries"],
             &(&1["event_kind"] == "workspace.hook.after_create")
           )
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

  test "GET status and logs expose AppKit runtime surface readbacks", %{conn: conn} do
    status = get(conn, ~p"/api/v1/status") |> json_response(200)

    assert status["operation"] == "status"
    assert status["data"]["schema_ref"] == "headless_runtime_status.v1"
    assert status["data"]["data"]["health"]["runtime"] == "ok"
    cleanup = status["data"]["data"]["health"]["startup_terminal_cleanup"]
    assert cleanup["last_cleanup_at"] == "2026-05-13T00:29:00Z"
    assert cleanup["candidate_count"] == 2
    assert cleanup["cleaned_count"] == 2
    assert cleanup["skipped_count"] == 0
    assert cleanup["failed_count"] == 0

    logs =
      conn
      |> recycle()
      |> get(~p"/api/v1/logs")
      |> json_response(200)

    assert logs["operation"] == "logs"
    assert logs["data"]["schema_ref"] == "headless_runtime_logs.v1"

    assert get_in(logs, ["data", "data", "entries", Access.at(0), "event_kind"]) ==
             "runtime_profile_applied"

    session_log =
      Enum.find(
        logs["data"]["data"]["entries"],
        &(&1["event_kind"] == "agent.session.event")
      )

    assert session_log["payload"]["issue_id"] == "ENG-42"
    assert session_log["payload"]["issue_identifier"] == "ENG-42"
    assert session_log["payload"]["session_id"] == "session:fixture"
    assert session_log["payload"]["trace_id"] == "trace:api"
    assert session_log["occurred_at"] == "2026-05-13T00:30:00Z"
    assert session_log["payload"]["credential_hint"] == "[redacted]"
    assert session_log["payload"]["workspace_hint"] == "[redacted-path]"
    refute Map.has_key?(session_log["payload"], "api_key")
    refute Map.has_key?(session_log["payload"], "workspace_path")

    encoded_logs = Jason.encode!(logs)
    refute encoded_logs =~ @secret
    refute encoded_logs =~ "/tmp/extravaganza"
  end

  @tag :tmp_dir
  test "profile validate and reload API routes use product import and AppKit apply", %{
    conn: conn,
    tmp_dir: tmp_dir
  } do
    workflow_path = write_workflow!(tmp_dir)
    cache_path = Path.join(tmp_dir, "last-good-profile.json")

    validate =
      post(conn, ~p"/api/v1/profile/validate", %{
        "workflow_path" => workflow_path,
        "env" => %{"LINEAR_API_KEY" => @secret}
      })
      |> json_response(200)

    assert validate["operation"] == "profile_validate"
    assert validate["data"]["status"] == "valid"
    refute Jason.encode!(validate) =~ @secret

    reload =
      conn
      |> recycle()
      |> post(~p"/api/v1/profile/reload", %{
        "workflow_path" => workflow_path,
        "profile_cache_path" => cache_path,
        "env" => %{"LINEAR_API_KEY" => @secret}
      })
      |> json_response(200)

    assert reload["operation"] == "profile_reload"
    assert reload["data"]["status"] == "reloaded"
    assert reload["data"]["runtime_profile_apply"]["status"] == "updated"
    assert reload["runtime_profile_ref"] == "runtime-profile://symphony-workflow"
    refute Jason.encode!(reload) =~ @secret
  end

  test "POST source-publication delegates to AppKit source publication surface", %{conn: conn} do
    body =
      post(conn, ~p"/api/v1/source-publication", %{
        "subject_ref" => "subject:fixture",
        "effect" => "comment"
      })
      |> json_response(200)

    assert body["operation"] == "source_publish"
    assert body["data"]["schema_ref"] == "headless_source_publication.v1"
    assert body["data"]["data"]["status"] == "receipt_recorded"
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
    read_execution_id = get_in(read, ["data", "data", "lease_ref", "execution_ref", "id"])
    assert read_execution_id
    assert get_in(read, ["data", "data", "scope", "subject_ref"]) == subject_id
    assert get_in(read, ["data", "data", "scope", "execution_ref"]) == read_execution_id
    assert get_in(read, ["data", "data", "scope", "source_revision_ref"])
    assert get_in(read, ["data", "data", "scope", "runtime_revision_ref"])
    assert get_in(read, ["data", "data", "scope", "invalidation", "lease_family"]) == "read"

    assert get_in(read, [
             "data",
             "data",
             "scope",
             "invalidation",
             "on_source_revision_change"
           ]) == true

    assert get_in(read, [
             "data",
             "data",
             "scope",
             "invalidation",
             "on_runtime_revision_change"
           ]) == true

    assert is_integer(get_in(read, ["data", "data", "invalidation_cursor"]))
    assert is_binary(get_in(read, ["data", "data", "invalidation_channel"]))

    stream =
      conn
      |> recycle()
      |> post(~p"/api/v1/subjects/#{subject_id}/stream-attach-lease", %{})
      |> json_response(200)

    assert stream["operation"] == "stream_attach_lease"
    assert stream["data"]["schema_ref"] == "headless_lease.v1"
    stream_execution_id = get_in(stream, ["data", "data", "lease_ref", "execution_ref", "id"])
    assert get_in(stream, ["data", "data", "scope", "subject_ref"]) == subject_id
    assert get_in(stream, ["data", "data", "scope", "execution_ref"]) == stream_execution_id
    assert get_in(stream, ["data", "data", "scope", "source_revision_ref"])
    assert get_in(stream, ["data", "data", "scope", "runtime_revision_ref"])

    assert get_in(stream, ["data", "data", "scope", "invalidation", "lease_family"]) ==
             "stream_attach"

    assert get_in(stream, [
             "data",
             "data",
             "scope",
             "invalidation",
             "on_source_revision_change"
           ]) == true

    assert get_in(stream, [
             "data",
             "data",
             "scope",
             "invalidation",
             "on_runtime_revision_change"
           ]) == true

    assert is_integer(get_in(stream, ["data", "data", "reconnect_cursor"]))
    assert is_binary(get_in(stream, ["data", "data", "invalidation_channel"]))
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

  defp write_workflow!(tmp_dir) do
    path = Path.join(tmp_dir, "WORKFLOW.md")

    File.write!(path, """
    ---
    tracker:
      kind: linear
      api_key: $LINEAR_API_KEY
      project_slug: ENG
    codex:
      command: codex app-server
    ---
    Ship {{ issue.identifier }}
    """)

    path
  end

  defmodule RuntimeBackend do
    @behaviour AppKit.Core.Backends.RuntimeBackend

    @impl true
    def apply_runtime_profile(context, runtime_profile, _opts) do
      RuntimeProfileApplyResult.new(%{
        status: :updated,
        tenant_ref: context.tenant_ref.id,
        profile_ref: "runtime-profile://symphony-workflow",
        program_ref: "program://#{get_in(runtime_profile, ["program", "slug"])}",
        policy_bundle_ref: "policy-bundle://symphony-workflow",
        work_class_ref: "work-class://symphony-workflow",
        placement_profile_ref: "placement-profile://symphony-workflow-local"
      })
    end

    @impl true
    def runtime_status(_context, _request, _opts) do
      RuntimeStatusSnapshot.new(%{
        tenant_ref: "extravaganza",
        program_ref: "program://symphony-workflow",
        health: %{
          "runtime" => "ok",
          "startup_terminal_cleanup" => %{
            "last_cleanup_at" => "2026-05-13T00:29:00Z",
            "candidate_count" => 2,
            "cleaned_count" => 2,
            "skipped_count" => 0,
            "failed_count" => 0,
            "receipt_refs" => [
              "cleanup-receipt://T-100",
              "cleanup-receipt://T-101"
            ]
          }
        },
        preflight: %{"linear" => "credential_present"}
      })
    end

    @impl true
    def runtime_logs(_context, _request, _opts) do
      RuntimeLogPage.new(%{
        entries: [
          %{
            ref: "runtime-log:fixture:1",
            event_kind: "runtime_profile_applied",
            occurred_at: "2026-05-11T00:00:00Z",
            summary: "Runtime profile applied",
            payload: %{"tenant_ref" => "extravaganza"}
          },
          %{
            ref: "runtime-log:fixture:2",
            event_kind: "agent.session.event",
            occurred_at: ~U[2026-05-13T00:30:00Z],
            summary: "Agent session emitted structured runtime log",
            payload: %{
              "tenant_ref" => "extravaganza",
              "issue_id" => "ENG-42",
              "issue_identifier" => "ENG-42",
              "session_id" => "session:fixture",
              "trace_id" => "trace:api",
              "credential_hint" => "linear-api-secret",
              "api_key" => "linear-api-secret",
              "workspace_hint" => "/tmp/extravaganza/ENG-42",
              "workspace_path" => "/tmp/extravaganza/ENG-42"
            }
          }
        ]
      })
    end

    @impl true
    def record_live_effect(_context, attrs, _opts), do: {:ok, attrs}

    @impl true
    def fetch_github_pr_evidence(_context, _request, _opts), do: {:error, :not_used}
  end

  defmodule SourceBackend do
    @behaviour AppKit.Core.Backends.SourceBackend

    @impl true
    def sync_linear_issues(_context, _source_page, _opts), do: {:ok, %{}}

    @impl true
    def current_linear_issue_states(_context, _issue_ids, _source_binding, _opts),
      do: {:ok, %{}}

    @impl true
    def fetch_linear_candidates(_context, source_binding, _opts) do
      {:ok,
       %{
         source_binding_id: Map.get(source_binding, :source_binding_id) || "linear-primary",
         source_intake: %{operation: "linear.issues.list", subject_attrs: []},
         provider_request_sent?: true,
         provider_response_received?: true
       }}
    end

    @impl true
    def publish_linear_source(context, attrs, _opts) do
      {:ok,
       %{
         "source_publication_receipt_ref" => "source-publication:fixture",
         "tenant_ref" => context.tenant_ref.id,
         "subject_ref" => Map.get(attrs, "subject_ref") || Map.get(attrs, :subject_ref),
         "status" => "receipt_recorded",
         "provider" => "linear",
         "effect" => Map.get(attrs, "effect") || Map.get(attrs, :effect)
       }}
    end

    @impl true
    def execute_linear_graphql_tool(_context, _attrs, _opts) do
      {:ok,
       %{
         operation: "linear.graphql.execute",
         tool_name: "linear_graphql",
         success?: true,
         dynamic_tool_response: %{"success" => true, "output" => ~s({"data":{}})}
       }}
    end
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
