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
  @allowed_prompt_variables MapSet.new([
                              "attempt",
                              "authorized_tool_refs",
                              "issue.assignee",
                              "issue.blockers",
                              "issue.description",
                              "issue.identifier",
                              "issue.labels",
                              "issue.priority",
                              "issue.state",
                              "issue.title",
                              "issue.url",
                              "max_turns",
                              "redaction_profile_ref",
                              "runtime_profile_ref",
                              "source_binding_ref",
                              "turn_number"
                            ])
  @allowed_prompt_filters MapSet.new(["default", "inspect", "join"])

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

  @spec compile_prompt_template(String.t(), keyword()) :: :ok | {:error, term()}
  def compile_prompt_template(template, opts \\ []) when is_binary(template) and is_list(opts) do
    allowed_variables =
      MapSet.new(Keyword.get(opts, :allowed_variables, @allowed_prompt_variables))

    allowed_filters = MapSet.new(Keyword.get(opts, :allowed_filters, @allowed_prompt_filters))

    with :ok <- balanced_template_tags(template) do
      template
      |> template_expressions()
      |> validate_template_expressions(allowed_variables, allowed_filters)
    end
  end

  @spec render_prompt_template(String.t(), map(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def render_prompt_template(template, attrs, opts \\ [])
      when is_binary(template) and is_map(attrs) and is_list(opts) do
    with {:ok, segments} <- parse_template(template),
         :ok <- compile_prompt_template(template, opts) do
      rendered =
        segments
        |> Enum.map(&render_template_segment(&1, attrs))
        |> IO.iodata_to_binary()

      {:ok, rendered}
    end
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

  defp balanced_template_tags(template) do
    case parse_template(template) do
      {:ok, _segments} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp template_expressions(template) do
    case parse_template(template) do
      {:ok, segments} ->
        Enum.flat_map(segments, fn
          {:expression, expression} -> [expression]
          {:text, _text} -> []
        end)

      {:error, _reason} ->
        []
    end
  end

  defp validate_template_expressions(expressions, allowed_variables, allowed_filters) do
    Enum.reduce_while(expressions, :ok, fn expression, :ok ->
      case validate_template_expression(expression, allowed_variables, allowed_filters) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_template_expression(expression, allowed_variables, allowed_filters) do
    [variable | filters] = expression |> String.split("|") |> Enum.map(&String.trim/1)

    cond do
      variable == "" ->
        {:error, {:template_render_error, %{reason: :empty_variable}}}

      not MapSet.member?(allowed_variables, variable) ->
        {:error, {:template_render_error, %{reason: :unknown_variable, variable: variable}}}

      true ->
        validate_template_filters(filters, allowed_filters)
    end
  end

  defp validate_template_filters(filters, allowed_filters) do
    Enum.reduce_while(filters, :ok, fn filter_expression, :ok ->
      filter_name = filter_expression |> String.split(":", parts: 2) |> hd() |> String.trim()

      if MapSet.member?(allowed_filters, filter_name) do
        {:cont, :ok}
      else
        {:halt,
         {:error, {:template_render_error, %{reason: :unknown_filter, filter: filter_name}}}}
      end
    end)
  end

  defp render_template_expression(expression, attrs) do
    [variable | filters] = expression |> String.split("|") |> Enum.map(&String.trim/1)

    attrs
    |> fetch_template_value(variable)
    |> apply_template_filters(filters)
    |> template_value_to_string()
  end

  defp fetch_template_value(attrs, variable) do
    variable
    |> String.split(".")
    |> Enum.reduce(attrs, fn key, value ->
      case value do
        value when is_map(value) -> Map.get(value, key) || Map.get(value, existing_atom(key))
        _other -> nil
      end
    end)
  end

  defp existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp parse_template(template), do: parse_template(template, [])

  defp parse_template(template, segments) do
    case split_once(template, "{{") do
      :nomatch ->
        if String.contains?(template, "}}") do
          {:error, {:template_parse_error, %{reason: :unbalanced_interpolation}}}
        else
          {:ok, Enum.reverse(add_text_segment(segments, template))}
        end

      {before_open, after_open} ->
        if String.contains?(before_open, "}}") do
          {:error, {:template_parse_error, %{reason: :unbalanced_interpolation}}}
        else
          parse_template_expression(after_open, before_open, segments)
        end
    end
  end

  defp parse_template_expression(after_open, before_open, segments) do
    case split_once(after_open, "}}") do
      :nomatch ->
        {:error, {:template_parse_error, %{reason: :unbalanced_interpolation}}}

      {expression, rest} ->
        next_segments =
          segments
          |> add_text_segment(before_open)
          |> add_expression_segment(expression)

        parse_template(rest, next_segments)
    end
  end

  defp add_text_segment(segments, ""), do: segments
  defp add_text_segment(segments, text), do: [{:text, text} | segments]

  defp add_expression_segment(segments, expression) do
    [{:expression, String.trim(expression)} | segments]
  end

  defp split_once(value, marker) do
    case :binary.match(value, marker) do
      :nomatch ->
        :nomatch

      {index, size} ->
        before_match = binary_part(value, 0, index)
        after_match = binary_part(value, index + size, byte_size(value) - index - size)
        {before_match, after_match}
    end
  end

  defp render_template_segment({:text, text}, _attrs), do: text

  defp render_template_segment({:expression, expression}, attrs) do
    render_template_expression(expression, attrs)
  end

  defp apply_template_filters(value, filters) do
    Enum.reduce(filters, value, fn filter_expression, value ->
      filter_expression
      |> String.split(":", parts: 2)
      |> case do
        ["default", default_value] -> default_filter(value, default_value)
        ["default"] -> default_filter(value, "")
        ["join", separator] -> join_filter(value, separator)
        ["join"] -> join_filter(value, ", ")
        ["inspect"] -> inspect(value)
        [_known] -> value
      end
    end)
  end

  defp default_filter(nil, default_value), do: trim_filter_arg(default_value)
  defp default_filter("", default_value), do: trim_filter_arg(default_value)
  defp default_filter(value, _default_value), do: value

  defp join_filter(value, separator) when is_list(value),
    do: Enum.join(value, trim_filter_arg(separator))

  defp join_filter(value, _separator), do: value

  defp trim_filter_arg(value) do
    value
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
  end

  defp template_value_to_string(nil), do: ""
  defp template_value_to_string(value) when is_binary(value), do: value
  defp template_value_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp template_value_to_string(value), do: to_string(value)
end
