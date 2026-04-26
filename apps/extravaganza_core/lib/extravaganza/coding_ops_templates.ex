defmodule Extravaganza.CodingOpsTemplates do
  @moduledoc """
  Product-owned prompt and workpad copy for the default coding-ops lane.
  """

  alias AppKit.Core.{
    EvidenceProjection,
    LowerReceiptSummary,
    ReviewProjection,
    RuntimeFactsProjection,
    SourceBindingProjection,
    SubjectRuntimeProjection
  }

  @prompt_ref "coding_agent_system"
  @workpad_template_ref "operator_review_workpad"

  @spec prompt_ref() :: String.t()
  def prompt_ref, do: @prompt_ref

  @spec workpad_template_ref() :: String.t()
  def workpad_template_ref, do: @workpad_template_ref

  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    # Extravaganza Coding Agent

    Prompt ref: #{@prompt_ref}

    ## Operating Contract

    You are executing one source-backed coding task for the Extravaganza
    product lane. Treat the admitted source item as the task of record and keep
    all provider identity, workspace identity, execution identity, and evidence
    identity tied to refs supplied by AppKit, Mezzanine, and lower receipts.

    ## Work Rules

    - Inspect the assigned workspace before editing.
    - Make the smallest production-quality change that satisfies the source
      task.
    - Keep tests and static checks aligned with the changed surface.
    - Preserve unrelated user work and report any blocking conflict.
    - Record durable evidence refs for the pull request, Codex session, lower
      receipt, and source workpad before requesting operator review.

    ## Review Handoff

    The final handoff must name the changed files, quality gates, evidence refs,
    and any residual risk. Do not invent provider object ids or require
    machine-local process state to locate provider state; provider refs must
    come from source admission, provider create/list output, workflow state, or
    durable receipts.

    Provider identity source: source admission, provider create/list output,
    workflow state, or durable receipts.
    """
  end

  @spec source_publication_preview(SubjectRuntimeProjection.t()) :: map()
  def source_publication_preview(%SubjectRuntimeProjection{} = projection) do
    source_binding = List.first(projection.source_bindings)
    review = review_projection(projection)
    body = projection |> workpad_attrs(source_binding, review) |> render_review_workpad()

    %{
      publish_ref: "linear_workpad_review",
      template_ref: @workpad_template_ref,
      operation: :update_comment,
      source_binding_ref: source_binding_ref(source_binding),
      subject_ref: projection.subject_ref,
      lifecycle_state: projection.lifecycle_state,
      body: body,
      lower_receipt_refs: Enum.map(projection.lower_receipts, & &1.receipt_ref),
      evidence_refs: Enum.map(projection.evidence, & &1.evidence_ref),
      pending_decision_refs: Enum.map(review.pending_decision_refs, & &1.id)
    }
  end

  @spec render_review_workpad(map()) :: String.t()
  def render_review_workpad(attrs) when is_map(attrs) do
    lower_receipts = Map.get(attrs, :lower_receipts, [])
    evidence = Map.get(attrs, :evidence, [])
    review = Map.get(attrs, :review) || %ReviewProjection{status: "none"}
    runtime = Map.get(attrs, :runtime) || %RuntimeFactsProjection{}

    """
    # Operator Review Workpad

    Status: #{value(attrs, :lifecycle_state, "awaiting_review")}
    Subject: #{value(attrs, :subject_ref, "subject unavailable")}
    Source: #{value(attrs, :source_ref, "source unavailable")}
    Source state: #{value(attrs, :source_state, "unknown")}
    Workspace: #{value(attrs, :workspace_ref, "workspace unavailable")}
    Execution: #{value(attrs, :execution_ref, "execution unavailable")}
    Dispatch: #{value(attrs, :dispatch_state, "unknown")}

    ## Source

    - Binding: #{value(attrs, :source_binding_ref, "binding unavailable")}
    - Kind: #{value(attrs, :source_kind, "unknown")}
    - URL: #{value(attrs, :source_url, "not projected")}
    - Workpads: #{joined(Map.get(attrs, :workpad_refs, []))}

    ## Lower Receipts

    #{lower_receipt_lines(lower_receipts)}

    ## Evidence

    #{evidence_lines(evidence)}

    ## Runtime

    - Tokens: #{inspect(runtime.token_totals)}
    - Rate limit: #{inspect(runtime.rate_limit)}
    - Events: #{runtime_event_lines(runtime.events)}

    ## Review

    - Status: #{review.status}
    - Pending decisions: #{joined(Enum.map(review.pending_decision_refs, & &1.id))}
    """
  end

  defp lower_receipt_lines([]), do: "- none"

  defp lower_receipt_lines(receipts) do
    Enum.map_join(receipts, "\n", fn %LowerReceiptSummary{} = receipt ->
      "- #{receipt.receipt_ref} #{receipt.receipt_state} #{receipt.lower_receipt_ref || "no lower ref"}"
    end)
  end

  defp evidence_lines([]), do: "- none"

  defp evidence_lines(evidence) do
    Enum.map_join(evidence, "\n", fn %EvidenceProjection{} = item ->
      "- #{item.evidence_kind} #{item.status} #{item.evidence_ref} #{item.content_ref || "no content ref"}"
    end)
  end

  defp runtime_event_lines([]), do: "none"

  defp runtime_event_lines(events) do
    Enum.map_join(events, ", ", &"#{&1.event_kind}=#{&1.count}")
  end

  defp workpad_attrs(%SubjectRuntimeProjection{} = projection, source_binding, review) do
    %{
      subject_ref: projection.subject_ref.id,
      lifecycle_state: projection.lifecycle_state,
      workspace_ref: maybe_id(projection.workspace_ref),
      execution_ref: execution_ref(projection.execution_state),
      dispatch_state: dispatch_state(projection.execution_state),
      lower_receipts: projection.lower_receipts,
      runtime: projection.runtime,
      evidence: projection.evidence,
      review: review
    }
    |> Map.merge(source_attrs(source_binding))
  end

  defp source_attrs(nil) do
    %{
      source_binding_ref: nil,
      source_ref: nil,
      source_kind: nil,
      source_state: nil,
      source_url: nil,
      workpad_refs: []
    }
  end

  defp source_attrs(%SourceBindingProjection{} = source_binding) do
    %{
      source_binding_ref: source_binding.binding_ref,
      source_ref: source_binding.source_ref,
      source_kind: source_binding.source_kind,
      source_state: source_binding.source_state,
      source_url: source_binding.source_url,
      workpad_refs: source_binding.workpad_refs
    }
  end

  defp review_projection(%SubjectRuntimeProjection{review: nil}),
    do: %ReviewProjection{status: "none"}

  defp review_projection(%SubjectRuntimeProjection{review: review}), do: review

  defp source_binding_ref(nil), do: nil

  defp source_binding_ref(%SourceBindingProjection{} = source_binding),
    do: source_binding.binding_ref

  defp execution_ref(nil), do: nil
  defp execution_ref(%{execution_ref: execution_ref}), do: maybe_id(execution_ref)

  defp dispatch_state(nil), do: nil
  defp dispatch_state(%{dispatch_state: dispatch_state}), do: dispatch_state

  defp maybe_id(nil), do: nil
  defp maybe_id(%{id: id}), do: id

  defp joined(nil), do: "none"
  defp joined([]), do: "none"
  defp joined(values) when is_list(values), do: Enum.join(values, ", ")

  defp value(attrs, key, default) do
    case Map.get(attrs, key) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) -> Atom.to_string(value)
      value when not is_nil(value) -> to_string(value)
      _ -> default
    end
  end
end
