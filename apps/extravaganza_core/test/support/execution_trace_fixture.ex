defmodule Extravaganza.TestSupport.ExecutionTraceFixture do
  @moduledoc false

  alias AppKit.Core.TraceIdentity
  alias Mezzanine.Audit.Repo, as: AuditRepo
  alias Mezzanine.Execution.Repo, as: ExecutionRepo

  @spec seed_execution_trace!(keyword()) :: %{execution_id: Ecto.UUID.t(), trace_id: String.t()}
  def seed_execution_trace!(opts) when is_list(opts) do
    tenant_id = Keyword.fetch!(opts, :tenant_id)
    installation_id = Keyword.fetch!(opts, :installation_id)
    subject_id = Keyword.fetch!(opts, :subject_id)
    recipe_ref = Keyword.get(opts, :recipe_ref, "triage_ticket")
    now = Keyword.get(opts, :occurred_at, ~U[2026-04-15 10:00:00Z])
    dispatch_state = Keyword.get(opts, :dispatch_state, "accepted_active")

    execution_attrs =
      opts
      |> Keyword.get(:execution_attrs, %{})
      |> normalize_execution_attrs()

    fact_kind = Keyword.get(opts, :fact_kind, "execution_dispatched")

    fact_payload =
      Keyword.get(opts, :fact_payload, %{
        "classification" => "accepted",
        "dispatch_state" => dispatch_state
      })

    extra_audit_facts = Keyword.get(opts, :extra_audit_facts, [])

    execution_id = Ecto.UUID.generate()
    trace_id = TraceIdentity.mint()
    causation_id = "cause-#{System.unique_integer([:positive])}"
    lower_run_id = "lower-run-#{System.unique_integer([:positive])}"

    {1, _} =
      ExecutionRepo.insert_all("execution_records", [
        Map.merge(
          %{
            id: dump_uuid!(execution_id),
            tenant_id: tenant_id,
            installation_id: installation_id,
            subject_id: dump_uuid!(subject_id),
            recipe_ref: recipe_ref,
            trace_id: trace_id,
            causation_id: causation_id,
            dispatch_state: dispatch_state,
            dispatch_attempt_count: 0,
            next_dispatch_at: now,
            submission_ref: %{"id" => "submission-#{execution_id}"},
            lower_receipt: %{"run_id" => lower_run_id},
            last_dispatch_error_payload: %{},
            row_version: 1,
            inserted_at: now,
            updated_at: now,
            compiled_pack_revision: 1,
            binding_snapshot: %{"placement_ref" => "local-session"},
            dispatch_envelope: %{},
            intent_snapshot: %{},
            submission_dedupe_key: Ecto.UUID.generate()
          },
          execution_attrs
        )
      ])

    audit_fact_rows =
      [
        %{
          id: dump_uuid!(Ecto.UUID.generate()),
          installation_id: installation_id,
          subject_id: subject_id,
          execution_id: execution_id,
          trace_id: trace_id,
          causation_id: causation_id,
          fact_kind: fact_kind,
          actor_ref: %{kind: :scheduler},
          payload: fact_payload,
          occurred_at: now,
          inserted_at: now,
          updated_at: now
        }
        | Enum.map(extra_audit_facts, fn attrs ->
            %{
              id: dump_uuid!(Ecto.UUID.generate()),
              installation_id: installation_id,
              subject_id: subject_id,
              execution_id: Map.get(attrs, :execution_id, execution_id),
              trace_id: Map.get(attrs, :trace_id, trace_id),
              causation_id: Map.get(attrs, :causation_id, causation_id),
              fact_kind: Map.fetch!(attrs, :fact_kind),
              actor_ref: Map.get(attrs, :actor_ref, %{kind: :scheduler}),
              payload: Map.get(attrs, :payload, %{}),
              occurred_at: Map.get(attrs, :occurred_at, now),
              inserted_at: Map.get(attrs, :inserted_at, now),
              updated_at: Map.get(attrs, :updated_at, now)
            }
          end)
      ]

    {count, _} = AuditRepo.insert_all("audit_facts", audit_fact_rows)
    true = count == length(audit_fact_rows)

    {1, _} =
      AuditRepo.insert_all("execution_lineage_records", [
        %{
          id: dump_uuid!(Ecto.UUID.generate()),
          trace_id: trace_id,
          causation_id: causation_id,
          tenant_id: tenant_id,
          installation_id: installation_id,
          subject_id: subject_id,
          execution_id: execution_id,
          ji_submission_key: "submission-#{execution_id}",
          lower_run_id: lower_run_id,
          lower_attempt_id: "attempt-1",
          artifact_refs: [],
          inserted_at: now,
          updated_at: now
        }
      ])

    %{execution_id: execution_id, trace_id: trace_id}
  end

  defp dump_uuid!(value) do
    case Ecto.UUID.dump(value) do
      {:ok, dumped} -> dumped
      :error -> raise ArgumentError, "invalid uuid: #{inspect(value)}"
    end
  end

  defp normalize_execution_attrs(attrs) when is_map(attrs) do
    attrs
    |> maybe_dump_uuid_attr(:barrier_id)
    |> maybe_dump_uuid_attr(:supersedes_execution_id)
  end

  defp normalize_execution_attrs(_attrs), do: %{}

  defp maybe_dump_uuid_attr(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) -> Map.put(attrs, key, dump_uuid!(value))
      _other -> attrs
    end
  end
end
