defmodule Extravaganza.ContextAIProductProof do
  @moduledoc false

  alias AppKit.ContextSurface

  @spec from_same_run(map()) :: {:ok, map()} | {:error, term()}
  def from_same_run(%{} = refs) do
    attrs = attrs(refs)

    with {:ok, context_packet} <- ContextSurface.packet_projection(attrs.context_packet),
         attrs <- put_context_packet_ref(attrs, context_packet.context_packet_ref),
         {:ok, route_decision} <- ContextSurface.route_decision_projection(attrs.route_decision),
         {:ok, model_invocation} <-
           ContextSurface.model_invocation_projection(attrs.model_invocation),
         {:ok, eval_verdict} <- ContextSurface.eval_verdict_projection(attrs.eval_verdict),
         {:ok, operator_review} <-
           ContextSurface.operator_review_projection(attrs.operator_review) do
      {:ok,
       %{
         "surface" => "AppKit.ContextSurface",
         "proof_class" => "extravaganza_context_ai_product_projection",
         "live_provider_required?" => false,
         "lower_stack_imports?" => false,
         "redaction_posture" => "refs_only",
         "context_packet" => projection_map(context_packet),
         "route_decision" => projection_map(route_decision),
         "model_invocation" => projection_map(model_invocation),
         "eval_verdict" => projection_map(eval_verdict),
         "operator_review" => projection_map(operator_review),
         "projection_facts" =>
           projection_facts(
             refs,
             context_packet,
             route_decision,
             model_invocation,
             eval_verdict,
             operator_review
           ),
         "forbidden_raw_fields_present?" => false
       }}
    end
  end

  def from_same_run(_refs), do: {:error, :invalid_context_ai_product_refs}

  defp attrs(refs) do
    trace_ref = trace_ref(refs)
    run_slug = safe_ref_fragment(refs.run_ref)
    context_packet_ref = "context-packet://extravaganza/same-run/#{run_slug}"
    route_decision_ref = "route-decision://extravaganza/same-run/#{run_slug}"
    model_receipt_ref = "model-receipt://extravaganza/same-run/#{run_slug}"
    eval_verdict_ref = "eval-verdict://extravaganza/same-run/#{run_slug}"
    prompt_artifact_ref = "prompt-artifact://extravaganza/same-run/#{run_slug}"
    provider_payload_ref = "provider-payload://extravaganza/same-run/#{run_slug}"

    %{
      context_packet: %{
        tenant_ref: "tenant://extravaganza/same-run",
        user_request_ref: "artifact://extravaganza/user-request/#{run_slug}",
        system_instruction_ref: "artifact://extravaganza/system-instruction/#{run_slug}",
        memory_refs: ["memory://extravaganza/same-run/#{safe_ref_fragment(refs.subject_ref)}"],
        budget_ref: "budget://extravaganza/same-run/#{run_slug}",
        model_class_allowlist: ["model-class://fixture"],
        route_policy_ref: "route-policy://extravaganza/same-run",
        trace_ref: trace_ref,
        receipt_ref: "context-packet-receipt://extravaganza/same-run/#{run_slug}",
        admission_status: :admitted
      },
      route_decision: %{
        route_decision_ref: route_decision_ref,
        context_packet_ref: context_packet_ref,
        route_policy_ref: "route-policy://extravaganza/same-run",
        selected_route_kind: :fixture,
        selected_model_profile_ref: "model-profile://fixture/extravaganza-same-run",
        provider_or_runtime_ref: "runtime://fixture/extravaganza-same-run",
        verifier_ref: "verifier://extravaganza/same-run",
        fallback_plan_ref: "fallback-plan://extravaganza/none",
        cost_estimate_ref: "cost-estimate://extravaganza/same-run/#{run_slug}",
        budget_status_ref: "budget-status://extravaganza/same-run/ok",
        authority_ref: refs.authority_ref,
        trace_ref: trace_ref,
        reason_codes: ["route.reason.fixture.v1", "route.reason.product_safe.v1"]
      },
      model_invocation: %{
        model_invocation_ref: "model-invocation://extravaganza/same-run/#{run_slug}",
        model_receipt_ref: model_receipt_ref,
        context_packet_ref: context_packet_ref,
        route_decision_ref: route_decision_ref,
        prompt_artifact_ref: prompt_artifact_ref,
        provider_payload_ref: provider_payload_ref,
        payload_hash: digest(provider_payload_ref),
        model_profile_ref: "model-profile://fixture/extravaganza-same-run",
        endpoint_ref: "endpoint://fixture/local",
        provider_ref: "provider://fixture",
        credential_lease_ref: "credential-lease://deterministic/same-run",
        cost_ref: "cost://extravaganza/same-run/#{run_slug}",
        trace_ref: trace_ref
      },
      eval_verdict: %{
        eval_verdict_ref: eval_verdict_ref,
        context_packet_ref: context_packet_ref,
        route_decision_ref: route_decision_ref,
        model_receipt_ref: model_receipt_ref,
        verdict: :pass,
        severity_class: "clean",
        decision_evidence_ref: refs.evidence_chain_ref,
        trace_ref: trace_ref
      },
      operator_review: %{
        review_ref: "review://extravaganza/same-run/#{safe_ref_fragment(refs.review_unit_id)}",
        context_packet_ref: context_packet_ref,
        route_decision_ref: route_decision_ref,
        eval_verdict_ref: eval_verdict_ref,
        promotion_refs: ["promotion://extravaganza/same-run/#{run_slug}"],
        rollback_refs: ["rollback://extravaganza/same-run/#{run_slug}"],
        operator_state: :pending,
        trace_refs: [trace_ref]
      }
    }
  end

  defp put_context_packet_ref(attrs, context_packet_ref) do
    attrs
    |> put_in([:route_decision, :context_packet_ref], context_packet_ref)
    |> put_in([:model_invocation, :context_packet_ref], context_packet_ref)
    |> put_in([:eval_verdict, :context_packet_ref], context_packet_ref)
    |> put_in([:operator_review, :context_packet_ref], context_packet_ref)
  end

  defp projection_facts(
         refs,
         context_packet,
         route_decision,
         model_invocation,
         eval_verdict,
         operator_review
       ) do
    %{
      "context_packet_ref" => context_packet.context_packet_ref,
      "packet_hash" => context_packet.packet_hash,
      "route_decision_ref" => route_decision.route_decision_ref,
      "model_invocation_ref" => model_invocation.model_invocation_ref,
      "model_receipt_ref" => model_invocation.model_receipt_ref,
      "eval_verdict_ref" => eval_verdict.eval_verdict_ref,
      "review_ref" => operator_review.review_ref,
      "prompt_artifact_ref" => model_invocation.prompt_artifact_ref,
      "provider_payload_ref" => model_invocation.provider_payload_ref,
      "payload_hash" => model_invocation.payload_hash,
      "projection_ref" =>
        "projection://extravaganza/context-ai/#{safe_ref_fragment(refs.run_ref)}"
    }
  end

  defp projection_map(struct) do
    struct
    |> Map.from_struct()
    |> Map.new(fn {key, value} -> {Atom.to_string(key), normalize(value)} end)
  end

  defp normalize(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)
  defp normalize(value), do: value

  defp trace_ref(%{trace_id: "trace://" <> suffix = trace_id}) when suffix != "", do: trace_id
  defp trace_ref(%{run_ref: run_ref}), do: "trace://extravaganza/same-run/#{run_ref}"

  defp digest(content) do
    hash =
      :crypto.hash(:sha256, content)
      |> Base.encode16(case: :lower)

    "sha256:" <> hash
  end

  defp safe_ref_fragment(value) when is_binary(value) do
    value
    |> String.replace(~r/[^A-Za-z0-9_.-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "ref"
      fragment -> fragment
    end
  end

  defp safe_ref_fragment(nil), do: "none"
  defp safe_ref_fragment(value), do: value |> to_string() |> safe_ref_fragment()
end
