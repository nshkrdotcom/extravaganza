defmodule Extravaganza.HeadlessJSONContractTest do
  use ExUnit.Case, async: false

  alias Extravaganza.{HeadlessJSON, HeadlessSurface}
  alias Extravaganza.Presenters.{EventPresenter, EvidencePresenter, RunPresenter}
  alias Extravaganza.TestSupport.FakeHeadlessBackend
  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

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

  test "success envelopes include stable refs without raw lower/provider material" do
    assert {:ok, run} = HeadlessSurface.run_detail("run:fixture")

    envelope =
      "run_detail"
      |> HeadlessJSON.success(RunPresenter.present(run), %{
        trace_id: "trace:test",
        idempotency_key: "idem:test",
        generated_at: "2026-05-08T00:00:00Z"
      })

    assert envelope["ok"] == true
    assert envelope["schema"] == "extravaganza.headless.response.v1"
    assert envelope["operation"] == "run_detail"
    assert envelope["trace_id"] == "trace:test"
    assert envelope["idempotency_key"] == "idem:test"
    assert envelope["runtime_profile_ref"] == "runtime-profile:local-deterministic"
    assert envelope["refs"]["run_ref"] == "run:fixture"
    assert envelope["refs"]["authority_ref"] == "authority:fixture"
    assert envelope["refs"]["connector_manifest_ref"] == "manifest:fixture"
    assert envelope["refs"]["capability_negotiation_ref"] == "capability-negotiation:fixture"
    assert envelope["refs"]["lower_request_ref"] == "lower-request:fixture"
    assert envelope["refs"]["lower_receipt_ref"] == "lower-receipt:fixture"
    assert run.runtime_row.state == "stalled"
    assert run.runtime_row.status_reason == "stall_timeout"
    assert Enum.any?(run.events, &(&1.event_kind == "runtime.stalled"))
    assert Enum.any?(run.retries, &(&1.reason == "stall_timeout" and &1.status == "scheduled"))

    encoded = Jason.encode!(envelope)
    refute String.contains?(encoded, "api_key")
    refute String.contains?(encoded, "provider_payload")
    refute String.contains?(encoded, "workspace_path")
    refute String.contains?(encoded, "/home/")
  end

  test "run detail JSON keeps the deterministic operator-visible field sets" do
    assert {:ok, run} = HeadlessSurface.run_detail("run:fixture")

    presented = RunPresenter.present(run)
    data = presented["data"]
    runtime_row = data["runtime_row"]
    extensions = runtime_row["extensions"]

    assert Map.keys(data) |> Enum.sort() == [
             "agent_loop_diagnostics",
             "budget_state",
             "candidate_fact_refs",
             "diagnostics",
             "events",
             "memory_proof_refs",
             "persistence_posture",
             "retries",
             "run_readback_coverage",
             "run_readback_coverage_gaps",
             "run_ref",
             "runtime_row",
             "schema_ref",
             "schema_version",
             "turns"
           ]

    assert Map.keys(runtime_row) |> Enum.sort() == [
             "execution_ref",
             "extensions",
             "persistence_posture",
             "polling_state",
             "provider_refs",
             "run_ref",
             "session_ref",
             "state",
             "status_reason",
             "subject_ref",
             "token_totals",
             "updated_at",
             "workflow_ref",
             "workspace_ref"
           ]

    assert Map.keys(extensions) |> Enum.sort() == [
             "acceptance",
             "continuation",
             "credential_preflight",
             "governance",
             "incident_bundles",
             "lower_envelope",
             "lower_receipt",
             "prompt_profile",
             "provider_request_response",
             "retry_receipts",
             "review_decision",
             "source_publication",
             "stall"
           ]

    assert Map.keys(extensions["provider_request_response"]) |> Enum.sort() == [
             "operation",
             "provider",
             "provider_request_ref",
             "provider_request_sent?",
             "provider_response_received?",
             "provider_response_ref",
             "raw_material_present?",
             "receipt_recorded?"
           ]

    assert Map.keys(extensions["source_publication"]) |> Enum.sort() == [
             "comment_ref",
             "mode",
             "source_publication_receipt_ref",
             "source_ref",
             "workpad_refs"
           ]

    assert [turn] = data["turns"]

    assert Map.keys(turn) |> Enum.sort() == [
             "continuation_prompt_ref",
             "continuation_turn_count",
             "lower_receipt_ref",
             "lower_request_ref",
             "max_turns",
             "max_turns_reached?",
             "profile_ref",
             "prompt_hash",
             "prompt_ref",
             "provider_session_id",
             "provider_turn_id",
             "sandbox_profile_ref",
             "session_ref",
             "source_contract_ref",
             "thread_ref",
             "turn_count",
             "turn_number",
             "turn_ref",
             "workspace_ref"
           ]

    envelope = HeadlessJSON.success(:run, presented, trace_id: "trace:shape")

    assert Map.keys(envelope) |> Enum.sort() == [
             "data",
             "generated_at",
             "ok",
             "operation",
             "refs",
             "runtime_profile_ref",
             "schema",
             "trace_id"
           ]

    assert Map.keys(envelope["refs"]) |> Enum.sort() == [
             "authority_ref",
             "capability_negotiation_ref",
             "connector_manifest_ref",
             "decision_ref",
             "lower_receipt_ref",
             "lower_request_ref",
             "run_ref",
             "runtime_profile_ref",
             "source_publication_ref",
             "subject_ref",
             "workflow_ref"
           ]
  end

  test "success and error envelopes redact caller-supplied live provider secret values" do
    secrets = %{
      linear_api_key: "lin_api_phase53_secret",
      github_token: "ghp_phase53_secret",
      gh_token: "gh_phase53_secret",
      openai_api_key: "sk-openai-phase53-secret",
      codex_api_key: "codex_phase53_secret"
    }

    success =
      HeadlessJSON.success(
        :live_linear_source,
        %{
          provider_effect: %{
            "neutral_detail" => "provider returned #{secrets.openai_api_key}",
            :linear_api_key => secrets.linear_api_key,
            :github_token => secrets.github_token,
            nested: [%{"codex_api_key" => secrets.codex_api_key}]
          }
        },
        Map.merge(secrets, %{generated_at: "2026-05-08T00:00:00Z"})
      )

    error =
      HeadlessJSON.error(
        :live_github_evidence,
        %AppKit.Core.SurfaceError{
          code: "provider_failed",
          message: "provider failed",
          kind: :provider,
          retryable: false,
          details: %{
            "neutral_detail" => "token #{secrets.gh_token}",
            openai_api_key: secrets.openai_api_key
          }
        },
        Map.merge(secrets, %{generated_at: "2026-05-08T00:00:00Z"})
      )

    encoded = Jason.encode!([success, error])

    for secret <- Map.values(secrets) do
      refute encoded =~ secret
    end

    refute encoded =~ "linear_api_key"
    refute encoded =~ "github_token"
    refute encoded =~ "gh_token"
    refute encoded =~ "openai_api_key"
    refute encoded =~ "codex_api_key"
    assert encoded =~ "[REDACTED]"
  end

  test "success envelopes extract same-run proof refs into the standard refs block" do
    envelope =
      HeadlessJSON.success(
        :smoke,
        %{
          "proof" => %{
            "subject_ref" => "subject://same-run",
            "run_ref" => "run://same-run",
            "workflow_ref" => "workflow://same-run",
            "runtime_profile_ref" => "runtime-profile://same-run",
            "authority_ref" => "authority://same-run",
            "decision_ref" => "decision://same-run",
            "connector_manifest_ref" => "manifest://same-run",
            "capability_negotiation_ref" => "capability-negotiation://same-run",
            "lower_request_ref" => "lower-request://same-run",
            "lower_receipt_ref" => "lower-receipt://same-run",
            "source_publication_ref" => "source-publication://same-run",
            "evidence_chain_ref" => "evidence-chain://same-run",
            "event_page_ref" => "event-page://same-run"
          }
        },
        generated_at: "2026-05-08T00:00:00Z"
      )

    assert envelope["refs"]["subject_ref"] == "subject://same-run"
    assert envelope["refs"]["run_ref"] == "run://same-run"
    assert envelope["refs"]["workflow_ref"] == "workflow://same-run"
    assert envelope["refs"]["authority_ref"] == "authority://same-run"
    assert envelope["refs"]["lower_request_ref"] == "lower-request://same-run"
    assert envelope["refs"]["lower_receipt_ref"] == "lower-receipt://same-run"
    assert envelope["refs"]["source_publication_ref"] == "source-publication://same-run"
    assert envelope["refs"]["evidence_chain_ref"] == "evidence-chain://same-run"
    assert envelope["refs"]["event_page_ref"] == "event-page://same-run"
  end

  test "success envelopes redact absolute workspace roots and cwd values" do
    envelope =
      HeadlessJSON.success(
        "workspace_readback",
        %{
          workspace: %{
            workspace_root: "/tmp/extravaganza/subject-1",
            cwd: "/tmp/extravaganza/subject-1",
            workspace_ref: "workspace://tenant-1/subject-1",
            path_redacted?: true
          }
        },
        generated_at: "2026-05-08T00:00:00Z"
      )

    encoded = Jason.encode!(envelope)

    refute String.contains?(encoded, "/tmp/extravaganza")
    assert String.contains?(encoded, "[redacted-path]")

    assert get_in(envelope, ["data", "workspace", "workspace_ref"]) ==
             "workspace://tenant-1/subject-1"
  end

  test "evidence chain and event page are first-class headless readback operations" do
    assert {:ok, evidence_chain} = HeadlessSurface.evidence_chain("run:fixture")
    evidence = EvidencePresenter.present(evidence_chain)

    assert evidence["schema_ref"] == "headless_evidence_chain.v1"
    assert evidence["data"]["lower"]["lower_runtime_kind"] == "deterministic_fixture"
    assert evidence["data"]["governance"]["authority_ref"] == "authority:fixture"

    assert evidence["data"]["source_publication"]["source_publication_receipt_ref"] ==
             "source-publication:fixture"

    assert {:ok, event_page} = HeadlessSurface.events(%{"run_id" => "run:fixture"})
    events = EventPresenter.present_page(event_page)

    assert events["schema_ref"] == "headless_events.v1"

    assert Enum.map(events["data"]["entries"], & &1["event_ref"]) ==
             Enum.map(0..15, &"event:run:#{&1}")

    hook_event =
      Enum.find(
        events["data"]["entries"],
        &(&1["event_kind"] == "workspace.hook.after_create")
      )

    assert hook_event["extensions"]["hook_receipt"]["stage"] == "after_create"
    assert hook_event["extensions"]["hook_receipt"]["path_redacted?"] == "true"
    refute Jason.encode!(hook_event) =~ "workspace_path"
    refute Jason.encode!(hook_event) =~ "/tmp/"

    stale_retry_event =
      Enum.find(
        events["data"]["entries"],
        &(&1["event_kind"] == "retry.stale_token_ignored")
      )

    assert stale_retry_event["extensions"]["safe_action"] == "ignore_retry"
    assert stale_retry_event["extensions"]["current_retry_retained?"] == "true"

    reconciliation_event =
      Enum.find(
        events["data"]["entries"],
        &(&1["event_kind"] == "cancel.terminal_source")
      )

    assert reconciliation_event["extensions"]["cancellation_reason"] == "terminal_source"
    assert reconciliation_event["extensions"]["workflow_signal"] == "operator.cancel"
  end

  test "evidence chain indexes every Symphony headless evidence category" do
    assert {:ok, evidence_chain} = HeadlessSurface.evidence_chain("run:fixture")

    assert evidence_chain["evidence_coverage_gaps"] == []

    coverage = evidence_chain["evidence_coverage"]

    assert Map.keys(coverage) |> Enum.sort() == [
             "authority_decision",
             "credential_preflight",
             "dispatch",
             "hook",
             "lower_run",
             "provider_request_response",
             "review_decision",
             "source_publication",
             "workspace_action"
           ]

    assert coverage["dispatch"]["refs"] == [
             "run:fixture",
             "execution:fixture",
             "workflow:fixture"
           ]

    assert coverage["credential_preflight"]["credential_present?"] == true
    assert coverage["credential_preflight"]["secret_material_present?"] == false
    assert coverage["credential_preflight"]["secret_material_redacted?"] == true

    assert coverage["authority_decision"]["authority_ref"] == "authority:fixture"
    assert coverage["authority_decision"]["decision_ref"] == "authority-decision:fixture"

    assert coverage["provider_request_response"]["provider_request_sent?"] == true
    assert coverage["provider_request_response"]["provider_response_received?"] == true

    assert coverage["provider_request_response"]["provider_request_ref"] ==
             "provider-request:fixture"

    assert coverage["provider_request_response"]["provider_response_ref"] ==
             "provider-response:fixture"

    assert coverage["lower_run"]["lower_request_ref"] == "lower-request:fixture"
    assert coverage["lower_run"]["lower_receipt_ref"] == "lower-receipt:fixture"

    assert coverage["hook"]["event_refs"] == ["event:run:7"]
    assert coverage["hook"]["hook_refs"] == ["hook:fixture:after_create"]

    assert coverage["workspace_action"]["workspace_ref"]["id"] == "workspace:fixture"
    assert coverage["workspace_action"]["workspace_ref"]["path_redacted?"] == true
    assert coverage["workspace_action"]["event_refs"] == ["event:run:7"]

    assert coverage["review_decision"]["review_unit_id"] == "review-unit:fixture"
    assert coverage["review_decision"]["decision_ref"] == "review-decision:fixture"

    assert coverage["source_publication"]["source_publication_receipt_ref"] ==
             "source-publication:fixture"

    encoded = Jason.encode!(coverage)
    refute encoded =~ "workspace_path"
    refute encoded =~ "/tmp/"
    refute encoded =~ "api_key"
    refute encoded =~ "credential_value"
  end

  test "event page indexes every Symphony headless timeline category" do
    assert {:ok, event_page} = HeadlessSurface.events(%{"run_id" => "run:fixture"})

    assert event_page["timeline_coverage_gaps"] == []

    coverage = event_page["timeline_coverage"]

    assert Map.keys(coverage) |> Enum.sort() == [
             "cancellation",
             "candidate_admission",
             "candidate_rejection",
             "codex_update",
             "dispatch",
             "hook",
             "publication",
             "reconciliation",
             "refresh_request",
             "retry",
             "scheduler_tick",
             "source_sync"
           ]

    assert coverage["scheduler_tick"]["event_kinds"] == ["scheduler.tick.started"]
    assert coverage["refresh_request"]["event_kinds"] == ["refresh.requested"]
    assert coverage["source_sync"]["event_kinds"] == ["source.sync.completed"]
    assert coverage["candidate_admission"]["event_kinds"] == ["candidate.admitted"]
    assert coverage["candidate_rejection"]["event_kinds"] == ["candidate.rejected"]
    assert coverage["dispatch"]["event_kinds"] == ["dispatch.started"]
    assert coverage["codex_update"]["event_kinds"] == ["codex.agent_message.updated"]
    assert coverage["hook"]["event_kinds"] == ["workspace.hook.after_create"]
    assert coverage["publication"]["event_kinds"] == ["source.publication.completed"]

    assert coverage["reconciliation"]["event_kinds"] == [
             "reconciliation.terminal_source_detected"
           ]

    assert coverage["cancellation"]["event_kinds"] == ["cancel.terminal_source"]

    assert coverage["retry"]["event_kinds"] == [
             "retry.scheduled",
             "retry.stale_token_ignored"
           ]

    encoded = Jason.encode!(event_page)
    refute encoded =~ "workspace_path"
    refute encoded =~ "/tmp/"
    refute encoded =~ "api_key"
    refute encoded =~ "credential_value"
  end

  test "error envelopes classify readback failures and preserve retry guidance" do
    envelope =
      HeadlessJSON.error("run_detail", :runtime_projection_not_found,
        trace_id: "trace:error",
        generated_at: "2026-05-08T00:00:00Z"
      )

    assert envelope["ok"] == false
    assert envelope["schema"] == "extravaganza.headless.error.v1"
    assert envelope["operation"] == "run_detail"
    assert envelope["error"]["code"] == "projection_unavailable"
    assert envelope["error"]["class"] == "readback_unavailable"
    assert envelope["error"]["retryable"] == true
    assert envelope["error"]["missing_refs"] == ["projection_ref"]
  end

  test "error envelopes classify every live/profile/provider/startup failure family" do
    cases = [
      {:live_product_path_required, "live_product_path_required", "missing_live_prerequisite",
       false, ["live_product_path"]},
      {{:invalid_workflow_config, "runtime profile mismatch"}, "invalid_workflow_config",
       "invalid_profile", false, ["workflow_profile"]},
      {%{
         "code" => "credential_not_supplied_to_product_command",
         "credential_refs" => ["LINEAR_API_KEY"]
       }, "credential_not_supplied_to_product_command", "missing_credential", false,
       ["provider_credential"]},
      {%AppKit.Core.SurfaceError{
         code: "provider_denied",
         message: "provider authority denied the request",
         kind: :authorization,
         retryable: false,
         details: %{lower_denial_ref: "lower-denial://provider/1"}
       }, "provider_denied", "provider_denial", false, []},
      {%AppKit.Core.SurfaceError{
         code: "provider_failed",
         message: "provider failed after dispatch",
         kind: :transient,
         retryable: true,
         details: %{provider_request_ref: "provider-request://1"}
       }, "provider_failed", "provider_error", true, []},
      {{:live_surface_dependency_failed, :req, {:not_started, :ssl}},
       "live_surface_dependency_failed", "app_not_started", true, ["live_surface_dependency"]},
      {:runtime_installation_not_provisioned, "runtime_installation_not_provisioned",
       "product_host_unavailable", true, ["runtime_installation_ref"]}
    ]

    for {reason, code, class, retryable?, missing_refs} <- cases do
      envelope =
        HeadlessJSON.error("failure_matrix", reason,
          trace_id: "trace:failure-matrix",
          generated_at: "2026-05-08T00:00:00Z"
        )

      assert envelope["ok"] == false
      assert envelope["schema"] == "extravaganza.headless.error.v1"
      assert envelope["operation"] == "failure_matrix"
      assert envelope["error"]["code"] == code
      assert envelope["error"]["class"] == class
      assert envelope["error"]["retryable"] == retryable?
      assert envelope["error"]["missing_refs"] == missing_refs
      assert is_binary(envelope["error"]["message"])
    end
  end

  test "Mix task startup errors use the same standard JSON error envelope" do
    envelope =
      TaskSupport.startup_error_envelope(
        {:live_surface_dependency_failed, :req, {:not_started, :ssl}},
        ["--json", "--trace-id", "trace:startup"]
      )

    assert envelope["ok"] == false
    assert envelope["schema"] == "extravaganza.headless.error.v1"
    assert envelope["operation"] == "startup"
    assert envelope["trace_id"] == "trace:startup"
    assert envelope["error"]["code"] == "live_surface_dependency_failed"
    assert envelope["error"]["class"] == "app_not_started"
    assert envelope["error"]["retryable"] == true
    assert envelope["error"]["missing_refs"] == ["live_surface_dependency"]
  end
end
