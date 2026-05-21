defmodule ExtravaganzaAgentFoundationProductTest do
  use ExUnit.Case, async: false

  alias Extravaganza.{AgentFoundationProduct, AgentRunViewModel}

  test "deterministic product proof enters through AppKit AgentIntake only" do
    assert {:ok, proof} =
             AgentFoundationProduct.deterministic_smoke(
               tenant_id: "extravaganza-agent-foundation-test",
               pack_version: "1.0.0-agent-foundation-test"
             )

    assert proof["proof_class"] == "extravaganza_agent_foundation_product"
    assert proof["appkit_surface"] == "AppKit.AgentIntake"
    assert proof["live_provider_required?"] == false
    assert proof["lower_stack_imports?"] == false
    assert proof["agent_interop_adapter?"] == false

    assert proof["operator_states"] == [
             "running",
             "pending_review",
             "catching_up",
             "replayed",
             "completed",
             "failed",
             "denied"
           ]

    assert get_in(proof, ["states", "running", "state"]) == "running"
    assert get_in(proof, ["states", "pending_review", "pending_ref"]) =~ "agent-pending://"
    assert get_in(proof, ["states", "catching_up", "event_count"]) == 3
    assert get_in(proof, ["states", "replayed", "lower_reexecution_allowed?"]) == false

    assert get_in(proof, ["states", "completed", "receipt_refs"]) == [
             "receipt://extravaganza/agent-foundation/runtime-1"
           ]

    assert get_in(proof, ["states", "failed", "error_class"]) == "projection_unavailable"

    assert get_in(proof, ["states", "denied", "decision_ref"]) ==
             "decision://extravaganza/agent-foundation/deny"

    assert proof["refs"]["ledger_ref"] == "agent-ledger://extravaganza/agent-foundation/run-1"

    assert proof["refs"]["evidence_export_ref"] ==
             "agent-evidence-export://extravaganza/agent-foundation/run-1"
  end

  test "product proof rejects lower selectors through AppKit DTO validation" do
    assert {:error, :invalid_agent_run_request} =
             AgentFoundationProduct.build_run_request(%{
               raw_endpoint: "https://provider.invalid/direct-call"
             })
  end

  test "view model exposes product-safe terminal and intermediate states" do
    assert %{"state" => "completed", "terminal?" => true} =
             AgentRunViewModel.terminal(:completed, %{
               run_ref: "agent-run://extravaganza/1",
               receipt_refs: ["receipt://extravaganza/1"]
             })

    assert %{"state" => "failed", "terminal?" => true, "error_class" => "timeout"} =
             AgentRunViewModel.failed(%{
               run_ref: "agent-run://extravaganza/1",
               error_class: "timeout"
             })

    assert %{"state" => "denied", "terminal?" => true} =
             AgentRunViewModel.denied(%{
               run_ref: "agent-run://extravaganza/1",
               decision_ref: "decision://extravaganza/deny"
             })
  end
end
