defmodule Extravaganza.AgentFoundationProduct do
  @moduledoc """
  Product-local proof wrapper for the native agent foundation.

  Extravaganza enters through AppKit AgentIntake and renders only product-safe
  refs, states, and evidence readbacks.
  """

  alias AppKit.AgentIntake

  alias AppKit.Core.AgentIntake.{
    AgentPendingInteraction,
    AgentRunCursor,
    AgentRunEventPage,
    AgentRunRequest,
    RunOutcomeFuture,
    TurnSubmission
  }

  alias Extravaganza.{AgentRunViewModel, AppKitContext, Config}

  @tenant_ref "tenant://extravaganza/agent-foundation"
  @actor_ref "actor://extravaganza/operator"
  @ledger_ref "agent-ledger://extravaganza/agent-foundation/run-1"
  @run_ref "agent-run://extravaganza/agent-foundation/run-1"
  @workflow_ref "workflow://extravaganza/agent-foundation/run-1"
  @pending_ref "agent-pending://extravaganza/agent-foundation/review-1"
  @decision_ref "decision://extravaganza/agent-foundation/review-1"
  @authority_ref "authority://extravaganza/agent-foundation/rev-1"
  @receipt_ref "receipt://extravaganza/agent-foundation/runtime-1"
  @evidence_export_ref "agent-evidence-export://extravaganza/agent-foundation/run-1"

  defmodule AgentOutcome do
    @moduledoc false

    defstruct [
      :run_ref,
      :ledger_ref,
      :state,
      :replay_ref,
      :event_count,
      :lower_reexecution_allowed?,
      :decision_ref,
      :authority_ref,
      :reason,
      :error_class,
      receipt_refs: [],
      evidence_refs: []
    ]
  end

  defmodule FixtureBackend do
    @moduledoc false

    @behaviour AppKit.Core.Backends.AgentIntakeBackend

    alias AppKit.Core.AgentIntake.{
      AgentPendingInteraction,
      AgentRunCursor,
      AgentRunEvent,
      AgentRunEventPage,
      RunOutcomeFuture
    }

    @impl true
    def start_agent_run(_context, request, _opts) do
      RunOutcomeFuture.new(%{
        run_ref: "agent-run://extravaganza/agent-foundation/run-1",
        workflow_ref: "workflow://extravaganza/agent-foundation/run-1",
        accepted?: true,
        command_ref: "command://extravaganza/agent-foundation/start",
        correlation_id: request.correlation_id,
        governed_effect_refs: %{
          "ledger_ref" => "agent-ledger://extravaganza/agent-foundation/run-1",
          "evidence_export_ref" => "agent-evidence-export://extravaganza/agent-foundation/run-1"
        }
      })
    end

    @impl true
    def submit_agent_turn(_context, submission, _opts) do
      RunOutcomeFuture.new(%{
        run_ref: submission.run_ref,
        workflow_ref: "workflow://extravaganza/agent-foundation/run-1",
        accepted?: true,
        command_ref: "command://extravaganza/agent-foundation/turn",
        correlation_id: "correlation://extravaganza/agent-foundation/turn",
        governed_effect_refs: %{"pending_ref" => submission.pending_ref}
      })
    end

    @impl true
    def cancel_agent_run(_context, run_ref, _opts) do
      RunOutcomeFuture.new(%{
        run_ref: run_ref,
        accepted?: true,
        command_ref: "command://extravaganza/agent-foundation/cancel",
        correlation_id: "correlation://extravaganza/agent-foundation/cancel"
      })
    end

    @impl true
    def await_agent_outcome(_context, run_ref, request, _opts) do
      mode = map_value(request, :mode) || :completed

      {:ok,
       %AgentOutcome{
         run_ref: run_ref,
         ledger_ref: "agent-ledger://extravaganza/agent-foundation/run-1",
         state: mode,
         replay_ref: replay_ref(mode),
         event_count: event_count(mode),
         lower_reexecution_allowed?: false,
         decision_ref: decision_ref(mode),
         authority_ref: "authority://extravaganza/agent-foundation/rev-1",
         reason: reason(mode),
         error_class: error_class(mode),
         receipt_refs: receipt_refs(mode),
         evidence_refs: ["agent-evidence-export://extravaganza/agent-foundation/run-1"]
       }}
    end

    @impl true
    def catch_up_agent_events(_context, cursor, _opts) do
      AgentRunEventPage.new(%{
        cursor: cursor,
        events: [
          event(
            3,
            :pending_opened,
            "Review opened",
            "agent-pending://extravaganza/agent-foundation/review-1"
          ),
          event(4, :pending_resolved, "Review approved", nil),
          event(5, :run_completed, "Run completed", nil)
        ],
        has_more?: false
      })
    end

    @impl true
    def list_pending_interactions(_context, request, _opts) do
      {:ok, pending} =
        AgentPendingInteraction.new(%{
          pending_ref: "agent-pending://extravaganza/agent-foundation/review-1",
          ledger_ref: "agent-ledger://extravaganza/agent-foundation/run-1",
          decision_ref: "decision://extravaganza/agent-foundation/review-1",
          tenant_ref: request.tenant_ref,
          actor_ref: request.actor_ref,
          kind: :approval_required,
          prompt_summary: "Approve deterministic product proof action",
          requested_action_ref: "action://extravaganza/agent-foundation/tool-call",
          authority_ref: "authority://extravaganza/agent-foundation/rev-1",
          opened_seq: 3,
          status: :open
        })

      {:ok, [pending]}
    end

    defp event(seq, kind, summary, pending_ref) do
      {:ok, event} =
        AgentRunEvent.new(%{
          event_ref: "agent-event://extravaganza/agent-foundation/#{seq}",
          ledger_ref: "agent-ledger://extravaganza/agent-foundation/run-1",
          event_seq: seq,
          event_kind: kind,
          visibility: :product,
          observed_at: "2026-05-21T00:00:0#{seq}Z",
          summary: summary,
          payload_ref: "payload://extravaganza/agent-foundation/#{seq}",
          pending_ref: pending_ref
        })

      event
    end

    defp map_value(%{} = attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
    defp replay_ref(:replayed), do: "agent-replay://extravaganza/agent-foundation/1"
    defp replay_ref("replayed"), do: "agent-replay://extravaganza/agent-foundation/1"
    defp replay_ref(_mode), do: nil
    defp event_count(:replayed), do: 5
    defp event_count("replayed"), do: 5
    defp event_count(_mode), do: nil
    defp decision_ref(:denied), do: "decision://extravaganza/agent-foundation/deny"
    defp decision_ref("denied"), do: "decision://extravaganza/agent-foundation/deny"
    defp decision_ref(_mode), do: nil
    defp reason(:denied), do: "capability_denied_before_dispatch"
    defp reason("denied"), do: "capability_denied_before_dispatch"
    defp reason(_mode), do: nil
    defp error_class(:failed), do: "projection_unavailable"
    defp error_class("failed"), do: "projection_unavailable"
    defp error_class(_mode), do: nil
    defp receipt_refs(:completed), do: ["receipt://extravaganza/agent-foundation/runtime-1"]
    defp receipt_refs("completed"), do: ["receipt://extravaganza/agent-foundation/runtime-1"]
    defp receipt_refs(_mode), do: []
  end

  @spec deterministic_smoke(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def deterministic_smoke(opts \\ []) do
    opts = opts |> opts_list() |> Keyword.put_new(:backend, FixtureBackend)
    config = Config.load(opts)
    context = AppKitContext.bootstrap_context(config, opts)

    with {:ok, request} <- build_run_request(%{}),
         {:ok, started} <- AgentIntake.start_agent_run(context, request, opts),
         {:ok, pending} <- pending_interaction(context, started, opts),
         {:ok, _turn_result} <- submit_review_turn(context, started, pending, opts),
         {:ok, event_page} <- catch_up(context, started, opts),
         {:ok, replayed} <- await(context, started.run_ref, :replayed, opts),
         {:ok, completed} <- await(context, started.run_ref, :completed, opts),
         {:ok, failed} <- await(context, started.run_ref, :failed, opts),
         {:ok, denied} <- await(context, started.run_ref, :denied, opts) do
      {:ok, proof(started, pending, event_page, replayed, completed, failed, denied)}
    end
  end

  @spec build_run_request(map()) :: {:ok, struct()} | {:error, term()}
  def build_run_request(attrs \\ %{}) when is_map(attrs) do
    attrs
    |> Map.merge(default_request_attrs(), fn _key, left, _right -> left end)
    |> AgentRunRequest.new()
  end

  defp pending_interaction(context, %RunOutcomeFuture{} = started, opts) do
    request = %{
      tenant_ref: @tenant_ref,
      actor_ref: @actor_ref,
      run_ref: started.run_ref,
      pending_ref: @pending_ref,
      status: :open
    }

    with {:ok, [pending | _]} <- AgentIntake.list_pending_interactions(context, request, opts) do
      {:ok, pending}
    end
  end

  defp submit_review_turn(
         context,
         %RunOutcomeFuture{} = started,
         %AgentPendingInteraction{} = pending,
         opts
       ) do
    submission =
      TurnSubmission.new!(%{
        idempotency_key: "idem-extravaganza-agent-foundation-review",
        actor_ref: @actor_ref,
        run_ref: started.run_ref,
        kind: :approval,
        payload_ref: "payload://extravaganza/agent-foundation/review-approved",
        pending_ref: pending.pending_ref
      })

    AgentIntake.submit_turn(context, submission, opts)
  end

  defp catch_up(context, %RunOutcomeFuture{}, opts) do
    cursor =
      AgentRunCursor.new!(%{
        cursor_ref: "agent-cursor://extravaganza/agent-foundation/after-2",
        ledger_ref: @ledger_ref,
        tenant_ref: @tenant_ref,
        actor_ref: @actor_ref,
        last_seq_seen: 2,
        visibility: :product,
        issued_at: "2026-05-21T00:00:02Z"
      })

    AgentIntake.catch_up_agent_events(context, %{cursor | ledger_ref: @ledger_ref}, opts)
  end

  defp await(context, run_ref, mode, opts) do
    AgentIntake.await_agent_outcome(context, run_ref, %{mode: mode}, opts)
  end

  defp proof(started, pending, event_page, replayed, completed, failed, denied) do
    %{
      "proof_class" => "extravaganza_agent_foundation_product",
      "receipt_ref" => "agent-foundation-product://extravaganza/deterministic",
      "appkit_surface" => "AppKit.AgentIntake",
      "live_provider_required?" => false,
      "lower_stack_imports?" => false,
      "agent_interop_adapter?" => false,
      "operator_states" => AgentRunViewModel.product_states(),
      "states" => %{
        "running" => AgentRunViewModel.running(started),
        "pending_review" => AgentRunViewModel.pending_review(pending),
        "catching_up" => AgentRunViewModel.catching_up(event_page),
        "replayed" => AgentRunViewModel.replayed(replayed),
        "completed" => AgentRunViewModel.terminal(:completed, completed),
        "failed" => AgentRunViewModel.failed(failed),
        "denied" => AgentRunViewModel.denied(denied)
      },
      "refs" => %{
        "run_ref" => @run_ref,
        "workflow_ref" => @workflow_ref,
        "ledger_ref" => @ledger_ref,
        "pending_ref" => @pending_ref,
        "decision_ref" => @decision_ref,
        "authority_ref" => @authority_ref,
        "runtime_receipt_refs" => [@receipt_ref],
        "evidence_export_ref" => @evidence_export_ref
      },
      "acceptance" => %{
        "AF-020" => %{
          "status" => "pass",
          "refs" => [
            "agent-foundation-product://extravaganza/deterministic",
            @ledger_ref
          ]
        }
      }
    }
  end

  defp default_request_attrs do
    %{
      tenant_ref: @tenant_ref,
      installation_ref: "installation://extravaganza/agent-foundation",
      subject_ref: "subject://extravaganza/agent-foundation/document-1",
      actor_ref: @actor_ref,
      profile_bundle: %{
        source_profile_ref: :extravaganza_agent_source,
        runtime_profile_ref: :extravaganza_agent_runtime,
        tool_scope_ref: :extravaganza_agent_tools,
        evidence_profile_ref: :extravaganza_agent_evidence,
        publication_profile_ref: :extravaganza_agent_publication,
        review_profile_ref: :extravaganza_agent_review,
        memory_profile_ref: :none,
        projection_profile_ref: :extravaganza_agent_projection
      },
      tool_catalog_ref: "tool-catalog://extravaganza/agent-foundation",
      budget_ref: "budget://extravaganza/agent-foundation",
      recall_scope_ref: "recall-scope://extravaganza/agent-foundation",
      idempotency_key: "idem-extravaganza-agent-foundation-start",
      trace_id: "trace://extravaganza/agent-foundation",
      correlation_id: "correlation://extravaganza/agent-foundation",
      submission_dedupe_key: "submission-extravaganza-agent-foundation-start",
      initial_input_ref: "payload://extravaganza/agent-foundation/initial-input",
      effect_governance_mode: :fixture_backed,
      diagnostic_lane: :echo
    }
  end

  defp opts_list(opts) when is_list(opts), do: opts
  defp opts_list(%{} = opts), do: Map.to_list(opts)
end
