defmodule Extravaganza.ContextAIProductProofTest do
  use ExUnit.Case, async: true

  alias Extravaganza.ContextAIProductProof

  test "projects context model and eval facts through AppKit only" do
    assert {:ok, summary} = ContextAIProductProof.from_same_run(refs())

    assert summary["surface"] == "AppKit.ContextSurface"
    assert summary["proof_class"] == "extravaganza_context_ai_product_projection"
    assert summary["live_provider_required?"] == false
    assert summary["lower_stack_imports?"] == false
    assert summary["forbidden_raw_fields_present?"] == false

    assert summary["context_packet"]["packet_hash"] =~ "sha256:"
    assert summary["context_packet"]["redaction_posture"] == "refs_only"
    assert summary["route_decision"]["selected_route_kind"] == "fixture"

    assert summary["model_invocation"]["prompt_artifact_ref"] =~ "prompt-artifact://"
    assert summary["model_invocation"]["provider_payload_ref"] =~ "provider-payload://"
    assert summary["model_invocation"]["payload_hash"] =~ "sha256:"
    assert summary["eval_verdict"]["verdict"] == "pass"
    assert summary["operator_review"]["operator_state"] == "pending"

    refute inspect(summary) =~ "raw_prompt"
    refute inspect(summary) =~ "provider_payload\"=>"
  end

  defp refs do
    %{
      subject_ref: "linear-work-object://tenant-1/work-1",
      run_ref: "run://tenant-1/run-1",
      authority_ref: "authority-decision://tenant-1/run-1",
      evidence_chain_ref: "evidence-chain://tenant-1/run-1",
      trace_id: "trace://tenant-1/run-1",
      review_unit_id: "review-unit://tenant-1/run-1"
    }
  end
end
