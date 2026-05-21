defmodule Extravaganza.AgentRunViewModel do
  @moduledoc """
  Product-safe view model for native agent run states.

  This module only consumes AppKit DTOs and Extravaganza product structs. It is
  intentionally detached from lower runtime ownership so web, headless, and
  operator readbacks can share one state vocabulary.
  """

  alias AppKit.Core.AgentIntake.{
    AgentPendingInteraction,
    AgentRunEventPage,
    RunOutcomeFuture
  }

  @states ~w[running pending_review catching_up replayed completed failed denied]

  @spec product_states() :: [String.t()]
  def product_states, do: @states

  @spec running(struct()) :: map()
  def running(%RunOutcomeFuture{} = future) do
    %{
      "state" => "running",
      "terminal?" => false,
      "run_ref" => future.run_ref,
      "workflow_ref" => future.workflow_ref,
      "command_ref" => future.command_ref,
      "correlation_id" => future.correlation_id,
      "accepted?" => future.accepted?
    }
  end

  @spec pending_review(struct()) :: map()
  def pending_review(%AgentPendingInteraction{} = pending) do
    %{
      "state" => "pending_review",
      "terminal?" => false,
      "pending_ref" => pending.pending_ref,
      "ledger_ref" => pending.ledger_ref,
      "decision_ref" => pending.decision_ref,
      "authority_ref" => pending.authority_ref,
      "requested_action_ref" => pending.requested_action_ref,
      "prompt_summary" => pending.prompt_summary,
      "opened_seq" => pending.opened_seq,
      "status" => Atom.to_string(pending.status)
    }
  end

  @spec catching_up(struct()) :: map()
  def catching_up(%AgentRunEventPage{} = page) do
    %{
      "state" => "catching_up",
      "terminal?" => false,
      "cursor_ref" => page.cursor.cursor_ref,
      "last_seq_seen" => page.cursor.last_seq_seen,
      "event_count" => length(page.events),
      "event_refs" => Enum.map(page.events, & &1.event_ref),
      "has_more?" => page.has_more?
    }
  end

  @spec replayed(map() | struct()) :: map()
  def replayed(outcome) do
    attrs = attrs(outcome)

    %{
      "state" => "replayed",
      "terminal?" => false,
      "run_ref" => value(attrs, :run_ref),
      "ledger_ref" => value(attrs, :ledger_ref),
      "replay_ref" => value(attrs, :replay_ref),
      "event_count" => value(attrs, :event_count) || 0,
      "lower_reexecution_allowed?" => value(attrs, :lower_reexecution_allowed?) == true
    }
  end

  @spec terminal(atom() | String.t(), map() | struct()) :: map()
  def terminal(state, outcome) when state in [:completed, "completed"] do
    attrs = attrs(outcome)

    %{
      "state" => "completed",
      "terminal?" => true,
      "run_ref" => value(attrs, :run_ref),
      "ledger_ref" => value(attrs, :ledger_ref),
      "receipt_refs" => List.wrap(value(attrs, :receipt_refs)),
      "evidence_refs" => List.wrap(value(attrs, :evidence_refs))
    }
  end

  @spec failed(map() | struct()) :: map()
  def failed(outcome) do
    attrs = attrs(outcome)

    %{
      "state" => "failed",
      "terminal?" => true,
      "run_ref" => value(attrs, :run_ref),
      "ledger_ref" => value(attrs, :ledger_ref),
      "error_class" => value(attrs, :error_class),
      "evidence_refs" => List.wrap(value(attrs, :evidence_refs))
    }
  end

  @spec denied(map() | struct()) :: map()
  def denied(outcome) do
    attrs = attrs(outcome)

    %{
      "state" => "denied",
      "terminal?" => true,
      "run_ref" => value(attrs, :run_ref),
      "ledger_ref" => value(attrs, :ledger_ref),
      "decision_ref" => value(attrs, :decision_ref),
      "authority_ref" => value(attrs, :authority_ref),
      "reason" => value(attrs, :reason)
    }
  end

  defp attrs(%_{} = struct), do: Map.from_struct(struct)
  defp attrs(%{} = map), do: map

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
