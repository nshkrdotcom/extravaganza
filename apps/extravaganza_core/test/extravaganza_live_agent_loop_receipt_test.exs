defmodule Extravaganza.LiveAgentLoopReceiptTest do
  use ExUnit.Case, async: false

  alias AppKit.Core.AgentIntake.RunOutcomeFuture

  alias AppKit.Core.RuntimeReadback.{
    RuntimeEventRow,
    RuntimeRow,
    RuntimeRunDetail
  }

  alias Extravaganza.{LiveAgentLoopReceipt, ProductPack}

  defmodule FakeLiveBackend do
    @behaviour AppKit.Core.Backends.AgentIntakeBackend
    @behaviour AppKit.Core.Backends.HeadlessBackend

    @run_ref "run://extravaganza/profile-a-live"
    @workflow_ref "workflow://agent-loop/extravaganza-profile-a-live"
    @turn_ref "turn://agent-loop/extravaganza-profile-a-live/1"
    @observed_at ~U[2026-04-27 12:00:00Z]

    @impl true
    def start_agent_run(_context, request, _opts) do
      RunOutcomeFuture.new(%{
        run_ref: @run_ref,
        workflow_ref: @workflow_ref,
        accepted?: true,
        command_ref: "command://#{request.idempotency_key}",
        correlation_id: request.correlation_id
      })
    end

    @impl true
    def submit_agent_turn(_context, _submission, _opts), do: {:error, :not_used}

    @impl true
    def cancel_agent_run(_context, _run_ref, _opts), do: {:error, :not_used}

    @impl true
    def await_agent_outcome(_context, _run_ref, _request, _opts), do: {:error, :not_used}

    @impl true
    def state_snapshot(_context, _request, _opts), do: {:error, :not_used}

    @impl true
    def runtime_subject_detail(_context, _subject_ref, _request, _opts), do: {:error, :not_used}

    @impl true
    def runtime_run_detail(_context, run_ref, _request, _opts) do
      with {:ok, runtime_row} <-
             RuntimeRow.new(%{
               subject_ref: "subject://extravaganza/live-profile-a",
               run_ref: run_ref,
               workflow_ref: @workflow_ref,
               state: "completed",
               updated_at: @observed_at,
               provider_refs: %{
                 "linear" => "provider-ref://linear/disposable-extravaganza-profile-a-live",
                 "github" => "provider-ref://github/disposable-extravaganza-profile-a-live",
                 "codex" => "provider-ref://codex/disposable-extravaganza-profile-a-live"
               }
             }),
           {:ok, event} <-
             RuntimeEventRow.new(%{
               event_ref: "event://agent-loop/extravaganza-profile-a-live/1",
               event_seq: 1,
               event_kind: "run.terminal",
               observed_at: @observed_at,
               subject_ref: "subject://extravaganza/live-profile-a",
               run_ref: run_ref,
               workflow_ref: @workflow_ref,
               turn_ref: @turn_ref,
               payload_ref: "payload://agent-loop/extravaganza-profile-a-live/terminal"
             }) do
        RuntimeRunDetail.new(%{
          run_ref: run_ref,
          runtime_row: runtime_row,
          events: [event],
          turns: [%{"turn_ref" => @turn_ref, "status" => "completed"}],
          candidate_fact_refs: ["candidate-fact://outer-brain/extravaganza-profile-a-live/1"],
          memory_proof_refs: ["m7a-proof://agent-loop/extravaganza-profile-a-live/1"]
        })
      end
    end

    @impl true
    def request_runtime_refresh(_context, _request, _opts), do: {:error, :not_used}

    @impl true
    def request_runtime_control(_context, _request, _opts), do: {:error, :not_used}
  end

  setup do
    previous_gate = System.get_env("STACK_CODER_LIVE_E2E")

    on_exit(fn ->
      if previous_gate do
        System.put_env("STACK_CODER_LIVE_E2E", previous_gate)
      else
        System.delete_env("STACK_CODER_LIVE_E2E")
      end
    end)

    :ok
  end

  test "product pack exposes an optional AgentLoop profile without changing M1 defaults" do
    assert ProductPack.profile_slots([]).memory_profile_ref == :none
    assert ProductPack.agent_loop_profile_slots([]).memory_profile_ref == :private_facts_v1
  end

  test "live receipt fixture preserves the Profile A public envelope and validates M2 proof refs" do
    offline =
      fixture!("receipts/agentic_substrate_headless_e2e_v1.json")

    live =
      fixture!("receipts/live/agentic_substrate_headless_e2e_v1.json")

    assert live["schema_ref"] == offline["schema_ref"]
    assert live["profile"] == offline["profile"]
    assert live["flavor"] == "live"
    assert live["mechanisms"] == ["M1", "M2"]
    assert live["appkit_surface"] == offline["appkit_surface"]
    assert "AppKit.AgentIntake" in live["appkit_surfaces"]
    assert :ok = LiveAgentLoopReceipt.validate_receipt(live)

    encoded = Jason.encode!(live)
    refute encoded =~ "workspace_path"
    refute encoded =~ "/home/"
    refute encoded =~ "raw_prompt"
    refute encoded =~ "raw_provider"
  end

  test "live Profile A M2 path fails closed when the explicit gate is absent" do
    assert {:error, :live_e2e_not_enabled} =
             LiveAgentLoopReceipt.run(%{}, backend: FakeLiveBackend)
  end

  test "process env cannot enable the live Profile A M2 path" do
    System.put_env("STACK_CODER_LIVE_E2E", "1")

    refute LiveAgentLoopReceipt.live_gate_enabled?()

    assert {:error, :live_e2e_not_enabled} =
             LiveAgentLoopReceipt.run(%{}, backend: FakeLiveBackend)

    assert LiveAgentLoopReceipt.live_gate_enabled?(live_e2e_enabled?: true)
  end

  if System.get_env("STACK_CODER_LIVE_E2E") == "1" do
    @tag :live
    @tag :live_e2e
    test "live-gated Profile A M2 path enters through AppKit and writes the receipt" do
      receipt_path =
        Path.join([
          "tmp",
          "test_receipts",
          "phase7",
          "agentic_substrate_headless_e2e_v1.json"
        ])

      attrs = %{
        turn_refs: ["turn://agent-loop/extravaganza-profile-a-live/1"],
        tool_action_receipt_refs: ["action-receipt://agent-loop/extravaganza-profile-a-live/1"],
        authority_decision_refs: ["authority-decision://agent-loop/extravaganza-profile-a-live/1"],
        candidate_fact_refs: ["candidate-fact://outer-brain/extravaganza-profile-a-live/1"],
        memory_commit_refs: ["memory-commit://agent-loop/extravaganza-profile-a-live/1"],
        provider_receipt_refs: [
          "provider-receipt://linear/disposable-extravaganza-profile-a-live",
          "provider-receipt://github/disposable-extravaganza-profile-a-live",
          "provider-receipt://codex/disposable-extravaganza-profile-a-live"
        ],
        cleanup_receipt_refs: [
          "cleanup-receipt://linear/disposable-extravaganza-profile-a-live",
          "cleanup-receipt://github/disposable-extravaganza-profile-a-live"
        ],
        disposable_provider_resource_refs: [
          "linear-issue://disposable/extravaganza-profile-a-live",
          "github-branch://disposable/extravaganza-profile-a-live",
          "codex-session://disposable/extravaganza-profile-a-live"
        ]
      }

      assert {:ok, receipt} =
               LiveAgentLoopReceipt.run(attrs,
                 backend: FakeLiveBackend,
                 live_e2e_enabled?: true,
                 receipt_path: receipt_path
               )

      assert File.exists?(receipt_path)
      assert receipt["mechanisms"] == ["M1", "M2"]
      assert receipt["memory_commit_refs"] == attrs.memory_commit_refs
      assert receipt["provider_credentials_required?"] == true
      assert receipt["headless_readback_hash"] =~ "sha256:"
      assert receipt["browser_presenter_hash"] =~ "sha256:"
      assert :ok = LiveAgentLoopReceipt.validate_receipt(receipt)
    end
  else
    @tag :live
    @tag :live_e2e
    @tag :skip
    test "live-gated Profile A M2 path enters through AppKit and writes the receipt" do
      :ok
    end
  end

  defp fixture!(relative_path) do
    "test/fixtures"
    |> Path.join(relative_path)
    |> File.read!()
    |> Jason.decode!()
  end
end
