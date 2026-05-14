defmodule Extravaganza.HeadlessSurfaceTest do
  use ExUnit.Case, async: false

  alias AppKit.Core.RuntimeReadback.{CommandResult, RuntimeRunDetail, RuntimeStateSnapshot}
  alias Extravaganza.{HeadlessSurface, ProductPack}

  alias Extravaganza.Presenters.{
    CommandResultPresenter,
    RunPresenter,
    StatePresenter,
    SubjectPresenter
  }

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

  test "product pack declares Phase 4 profile slots without requiring M2" do
    slots = ProductPack.profile_slots([])

    assert slots.source_profile_ref == :linear_coding_task
    assert slots.runtime_profile_ref == :codex_session
    assert slots.memory_profile_ref == :none
    assert slots.projection_profile_ref == :coding_ops_projection_v1
  end

  test "HeadlessSurface reads fixture M1 state through AppKit only" do
    assert {:ok, %RuntimeStateSnapshot{} = snapshot} = HeadlessSurface.state_snapshot(%{})

    states = Enum.map(snapshot.rows, & &1.state)

    assert "running" in states
    assert "retrying" in states
    assert "review_pending" in states
    assert "terminal_success" in states
    assert "terminal_failure" in states
    assert "input_required" in states
    assert "approval_required" in states
    assert "cancelled" in states
    assert "authority_denied" in states

    rendered = StatePresenter.present(snapshot, correlation_id: "corr:test")

    assert rendered["schema_ref"] == "headless_state_snapshot.v1"
    assert rendered["correlation_id"] == "corr:test"
    assert rendered["data"]["turns"] == []

    orchestrator_state = rendered["data"]["symphony_orchestrator_state"]

    assert orchestrator_state["mapped_from"] == "appkit_runtime_readback"
    assert orchestrator_state["counts"] == %{"running" => 1, "retrying" => 2, "completed" => 1}
    assert Enum.map(orchestrator_state["running"], & &1["subject_ref"]) == ["subject:running"]
    assert orchestrator_state["claimed"] == ["subject:running"]
    assert orchestrator_state["completed"] == ["subject:terminal-success"]

    assert [running] = orchestrator_state["running"]
    assert running["session_id"] == "session:running"
    assert running["turn_count"] == 7
    assert running["started_at"] == "2026-04-27T00:00:00Z"
    assert running["last_event"] == "turn_completed"
    assert running["last_message"] == "fixture turn completed"
    assert running["last_event_at"] == "2026-04-27T00:09:00Z"

    assert running["tokens"] == %{
             "input_tokens" => 120,
             "output_tokens" => 45,
             "total_tokens" => 165
           }

    assert orchestrator_state["profile_refs"] == %{
             "runtime_profile_ref" => "runtime-profile:codex-session-fixture",
             "projection_profile_ref" => "projection-profile:coding-ops-fixture"
           }

    assert orchestrator_state["slots"] == %{
             "available" => 2,
             "max" => 3,
             "running" => 1
           }

    assert orchestrator_state["source_sync"] == %{
             "status" => "fresh",
             "source_ref" => "source:linear:ENG-42",
             "last_synced_at" => "2026-04-27T00:08:55Z"
           }

    assert orchestrator_state["reconciliation_warnings"] == [
             %{
               "code" => "source_state_stale",
               "message" => "Source state is older than runtime projection",
               "source_ref" => "source:linear:ENG-42"
             }
           ]

    assert orchestrator_state["retrying"] == [
             %{
               "attempt" => "attempt:retrying:2",
               "due_at" => "2026-04-27T00:10:00Z",
               "error" => "transient failure",
               "status" => "scheduled"
             },
             %{
               "attempt" => "attempt:retrying:3",
               "due_at" => "2026-04-27T00:20:00Z",
               "error" => "agent exited",
               "status" => "scheduled"
             }
           ]

    assert orchestrator_state["retry_attempts"] == [
             %{
               "attempt_ref" => "attempt:retrying:2",
               "continuation?" => true,
               "delay_ms" => 1000,
               "delay_type" => "continuation",
               "due_at" => "2026-04-27T00:10:00Z",
               "next_due_at" => "2026-04-27T00:10:00Z",
               "status" => "scheduled",
               "reason" => "transient failure",
               "scheduled_at" => "2026-04-27T00:10:00Z"
             },
             %{
               "attempt_ref" => "attempt:retrying:3",
               "delay_ms" => 20_000,
               "delay_type" => "failure_backoff",
               "due_at" => "2026-04-27T00:20:00Z",
               "next_due_at" => "2026-04-27T00:20:00Z",
               "status" => "scheduled",
               "reason" => "agent exited",
               "scheduled_at" => "2026-04-27T00:20:00Z"
             }
           ]

    assert orchestrator_state["codex_totals"] == %{
             "input_tokens" => 1200,
             "output_tokens" => 450,
             "total_tokens" => 1650,
             "seconds_running" => 0,
             "source" => "runtime:event:tokens"
           }

    assert orchestrator_state["codex_rate_limits"] == [
             %{
               "limit_id" => "rate:codex:minute",
               "name" => "fixture runtime",
               "remaining" => 99,
               "reset_at" => "2026-04-27T00:01:00Z",
               "window" => "minute",
               "source_event_ref" => "event:rate"
             }
           ]

    assert orchestrator_state["polling"] == %{
             "checking?" => false,
             "last_refresh_command_ref" => "command:refresh:last",
             "next_poll_at" => "2026-04-27T00:01:00Z",
             "poll_interval_ms" => 60_000,
             "staleness_ms" => 0
           }

    refute String.contains?(Jason.encode!(rendered), "workspace_path")
    refute String.contains?(Jason.encode!(rendered), "/home/")
  end

  test "subject and run presenters pass through future M2 event slots safely" do
    assert {:ok, subject} = HeadlessSurface.subject_detail("subject:fixture")
    rendered_subject = SubjectPresenter.present(subject)

    event_kinds = Enum.map(rendered_subject["data"]["events"], & &1["event_kind"])
    assert "future_m2_state_added" in event_kinds
    assert rendered_subject["data"]["agent_loop_diagnostics"] == []

    assert {:ok, %RuntimeRunDetail{} = run} = HeadlessSurface.run_detail("run:fixture")
    rendered_run = RunPresenter.present(run)

    assert Enum.map(rendered_run["data"]["events"], & &1["event_seq"]) == Enum.to_list(0..15)

    hook_event =
      Enum.find(
        rendered_run["data"]["events"],
        &(&1["event_kind"] == "workspace.hook.after_create")
      )

    assert hook_event["message_summary"] == "after_create hook completed"
    assert hook_event["extensions"]["hook_receipt"]["hook_ref"] == "hook:fixture:after_create"
    assert hook_event["extensions"]["hook_receipt"]["stage"] == "after_create"
    assert hook_event["extensions"]["hook_receipt"]["status"] == "succeeded"
    assert hook_event["extensions"]["hook_receipt"]["path_redacted?"] == true
    refute Jason.encode!(hook_event) =~ "workspace_path"
    refute Jason.encode!(hook_event) =~ "/tmp/"

    stale_retry_event =
      Enum.find(
        rendered_run["data"]["events"],
        &(&1["event_kind"] == "retry.stale_token_ignored")
      )

    assert stale_retry_event["message_summary"] == "Stale retry timer ignored"
    assert stale_retry_event["extensions"]["safe_action"] == "ignore_retry"
    assert stale_retry_event["extensions"]["dispatch_allowed?"] == false
    assert stale_retry_event["extensions"]["current_retry_retained?"] == true

    reconciliation_event =
      Enum.find(
        rendered_run["data"]["events"],
        &(&1["event_kind"] == "cancel.terminal_source")
      )

    assert reconciliation_event["message_summary"] == "Terminal source cancelled lower run"
    assert reconciliation_event["extensions"]["cancellation_reason"] == "terminal_source"
    assert reconciliation_event["extensions"]["workflow_signal"] == "operator.cancel"
    assert reconciliation_event["extensions"]["projection_mutation"] == "complete_subject"
    assert reconciliation_event["extensions"]["cleanup_required?"] == true

    assert rendered_run["data"]["memory_proof_refs"] == []
    assert rendered_run["data"]["persistence_posture"]["durable?"] == false

    assert rendered_run["data"]["retries"] == [
             %{
               "attempt_ref" => "attempt:fixture:stall:2",
               "delay_ms" => 10_000,
               "delay_type" => "failure_backoff",
               "due_at" => "2026-04-27T00:10:10Z",
               "metadata" => %{"safe_action" => "terminate_lower_and_schedule_retry"},
               "reason" => "stall_timeout",
               "retry_ref" => "retry:fixture:stall:2",
               "scheduled_at" => "2026-04-27T00:10:00Z",
               "status" => "scheduled",
               "worker_ref" => "worker:fixture",
               "workspace_ref" => "workspace:fixture"
             },
             %{
               "attempt_ref" => "attempt:fixture:1",
               "continuation?" => true,
               "delay_ms" => 1000,
               "delay_type" => "continuation",
               "due_at" => "2026-04-27T00:10:00Z",
               "reason" => "source_still_active",
               "scheduled_at" => "2026-04-27T00:10:00Z",
               "status" => "scheduled",
               "worker_ref" => "worker:fixture",
               "workspace_ref" => "workspace:fixture"
             },
             %{
               "attempt_ref" => "attempt:fixture:2",
               "delay_ms" => 20_000,
               "delay_type" => "failure_backoff",
               "due_at" => "2026-04-27T00:20:00Z",
               "reason" => "agent exited",
               "scheduled_at" => "2026-04-27T00:20:00Z",
               "status" => "scheduled",
               "worker_ref" => "worker:fixture",
               "workspace_ref" => "workspace:fixture"
             }
           ]

    assert rendered_run["data"]["persistence_posture"]["retention_policy_ref"] ==
             "retention://lost-on-process-exit"

    encoded_run = Jason.encode!(rendered_run)
    refute String.contains?(encoded_run, "restart_safe")
    refute String.contains?(encoded_run, "integration_postgres")
  end

  test "refresh and control commands return typed command results" do
    assert {:ok, %CommandResult{} = refresh} =
             HeadlessSurface.request_refresh(%{"idempotency_key" => "idem:refresh"})

    assert refresh.command_kind == "refresh"
    assert refresh.workflow_effect_state == "pending_signal"
    assert refresh.coalesced? == false

    assert_receive {:headless_refresh_request, refresh_request}
    assert refresh_request.operations == ["poll", "reconcile"]
    assert refresh_request.reason == "manual_refresh"

    rendered_refresh = CommandResultPresenter.present(refresh, correlation_id: "corr:refresh")
    assert rendered_refresh["data"]["coalesced?"] == false

    assert {:ok, %CommandResult{} = denied} =
             HeadlessSurface.request_control("subject:fixture", "cancel", %{
               "idempotency_key" => "idem:cancel",
               "deny" => "true"
             })

    assert denied.accepted? == false
    assert denied.workflow_effect_state == "rejected_by_authority"
    assert List.last(denied.authority_refs) == "authority:decision-denied"

    for {legacy_action, public_action} <- [
          {"pause_execution", "pause"},
          {:resume_execution, "resume"},
          {"cancel_execution", "cancel"},
          {:request_rework, "rework"}
        ] do
      assert {:ok, %CommandResult{} = aliased} =
               HeadlessSurface.request_control("subject:fixture", legacy_action, %{
                 "idempotency_key" => "idem:#{public_action}"
               })

      assert aliased.command_kind == public_action
    end

    rendered = CommandResultPresenter.present(denied, correlation_id: "corr:denied")
    assert rendered["schema_ref"] == "headless_command_result.v1"
  end

  test "offline M1 receipt validates the required proof taxonomy" do
    receipt =
      "test/fixtures/receipts/agentic_substrate_headless_e2e_v1.json"
      |> File.read!()
      |> Jason.decode!()

    assert receipt["schema_ref"] == "agentic_substrate_headless_e2e_v1"
    assert receipt["mechanism"] == "M1"
    assert receipt["agent_loop_used?"] == false
    assert receipt["memory_profile_ref"] == "none"
    assert receipt["provider_credentials_required?"] == false
    assert receipt["network_required?"] == false
    assert receipt["receipt_state"] == "proven"
  end
end

defmodule Extravaganza.HeadlessSharedPresenterBoundaryTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  test "browser and API controllers import the shared headless presenters" do
    browser =
      File.read!(
        Path.join(@root, "extravaganza_web/lib/extravaganza_web/controllers/page_controller.ex")
      )

    api =
      File.read!(
        Path.join(
          @root,
          "extravaganza_web/lib/extravaganza_web/controllers/api/headless_controller.ex"
        )
      )

    assert String.contains?(browser, "StatePresenter")
    assert String.contains?(browser, "SubjectPresenter")
    assert String.contains?(browser, "ReviewPresenter")

    assert String.contains?(api, "StatePresenter")
    assert String.contains?(api, "SubjectPresenter")
    assert String.contains?(api, "RunPresenter")
    assert String.contains?(api, "CommandResultPresenter")
  end
end
