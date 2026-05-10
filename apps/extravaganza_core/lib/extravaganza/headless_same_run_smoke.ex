defmodule Extravaganza.HeadlessSameRunSmoke do
  @moduledoc false

  alias AppKit.Core.RuntimeReadback.RuntimeRunDetail
  alias Extravaganza.{HeadlessJSON, ProductHost}

  @readback_names ~w[
    state
    queue
    subject
    run
    evidence
    events
    reviews
    review_decision
    source_preview
    source_publication
    refresh
    control
    read_lease
    stream_attach_lease
  ]

  @spec run(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    opts = opts_map(opts)
    product_opts = product_opts(opts)
    subject_attrs = linear_subject(opts)

    with {:ok, start_result} <- ProductHost.start_run(subject_attrs, product_opts),
         {:ok, refs} <- refs_from_start(start_result),
         same_run = same_run_context(refs, start_result, subject_attrs),
         readback_opts = readback_opts(product_opts, same_run),
         {:ok, state} <- ProductHost.state_snapshot(%{}, product_opts),
         {:ok, queue} <- ProductHost.operator_queue(%{}, product_opts),
         {:ok, subject} <- ProductHost.subject_detail(refs.subject_ref, product_opts),
         {:ok, run} <-
           ProductHost.run_detail(refs.run_ref, run_request(refs, same_run), product_opts),
         {:ok, evidence} <-
           ProductHost.evidence_chain(refs.run_ref, run_request(refs, same_run), product_opts),
         {:ok, events} <-
           ProductHost.events(
             %{
               "run_id" => refs.run_ref,
               "agent_loop_projection" => same_run.agent_loop_projection
             },
             product_opts
           ),
         {:ok, reviews} <- ProductHost.pending_reviews(%{}, product_opts),
         {:ok, review_decision} <-
           ProductHost.record_review_decision(
             review_identity(reviews),
             %{decision: :accept, reason: "accepted by deterministic same-run smoke"},
             product_opts
           ),
         {:ok, source_preview} <-
           ProductHost.source_publication_preview(refs.subject_ref, readback_opts),
         {:ok, refresh} <-
           ProductHost.request_refresh(
             %{"idempotency_key" => "same-run-refresh:#{refs.run_ref}"},
             product_opts
           ),
         {:ok, control} <-
           ProductHost.request_control(
             refs.subject_ref,
             :retry,
             %{"idempotency_key" => "same-run-control:#{refs.run_ref}"},
             product_opts
           ),
         {:ok, read_lease} <- ProductHost.issue_read_lease(refs.subject_ref, readback_opts),
         {:ok, stream_attach_lease} <-
           ProductHost.issue_stream_attach_lease(refs.subject_ref, readback_opts) do
      proof =
        proof(refs, %{
          state: state,
          queue: queue,
          subject: subject,
          run: run,
          evidence: evidence,
          events: events,
          reviews: reviews,
          review_decision: review_decision,
          source_preview: source_preview,
          source_publication: source_publication_receipt(refs, source_preview),
          refresh: refresh,
          control: control,
          read_lease: read_lease,
          stream_attach_lease: stream_attach_lease
        })

      assert_same_run!(proof)

      {:ok,
       %{
         "proof" => proof,
         "start" => start_summary(refs, start_result),
         "readbacks" => proof["readbacks"]
       }}
    end
  end

  @spec assert_same_run!(map()) :: :ok
  def assert_same_run!(%{} = proof) do
    expected =
      Map.take(proof, ~w[subject_ref run_ref workflow_ref evidence_chain_ref event_page_ref])

    mismatches =
      proof
      |> Map.get("readbacks", [])
      |> Enum.reject(fn readback ->
        Enum.all?(expected, fn {key, value} -> Map.get(readback, key) == value end)
      end)

    if mismatches == [] do
      :ok
    else
      names = Enum.map(mismatches, &Map.get(&1, "name"))
      raise ArgumentError, "same-run readback refs diverged: #{Enum.join(names, ", ")}"
    end
  end

  def assert_same_run!(_proof), do: raise(ArgumentError, "invalid same-run proof")

  defp refs_from_start(start_result) do
    payload = start_result.payload
    run_ref = Map.fetch!(payload, :run_ref)
    metadata = run_ref.metadata || %{}
    subject_ref = Map.fetch!(payload, :work_object_id)
    workflow_ref = Map.fetch!(payload, :workflow_start_ref)
    execution_id = Map.fetch!(payload, :execution_id)

    {:ok,
     %{
       subject_ref: subject_ref,
       run_ref: run_ref.run_id,
       workflow_ref: workflow_ref,
       runtime_profile_ref: Map.get(metadata, :runtime_profile_ref),
       authority_ref: "authority-packet://pending/#{run_ref.run_id}",
       decision_ref: "permission-decision://pending/#{run_ref.run_id}",
       connector_manifest_ref: "connector-manifest://pending/#{run_ref.run_id}",
       capability_negotiation_ref: "capability-negotiation://pending/#{run_ref.run_id}",
       lower_request_ref: "lower-request://pending/#{run_ref.run_id}",
       lower_receipt_ref: "lower-receipt://pending/#{execution_id}",
       source_publication_ref: "source-publication://deterministic-same-run/#{run_ref.run_id}",
       evidence_chain_ref: "evidence-chain:#{run_ref.run_id}",
       event_page_ref: "event-page:#{run_ref.run_id}",
       execution_ref: execution_id,
       trace_id: Map.get(metadata, :trace_id),
       review_unit_id: Map.get(payload, :review_unit_id)
     }}
  rescue
    KeyError -> {:error, :invalid_start_result}
  end

  defp proof(refs, readbacks) do
    readback_rows =
      Enum.map(@readback_names, fn name ->
        data = Map.fetch!(readbacks, String.to_existing_atom(name))

        refs
        |> Map.take([
          :subject_ref,
          :run_ref,
          :workflow_ref,
          :runtime_profile_ref,
          :authority_ref,
          :decision_ref,
          :connector_manifest_ref,
          :capability_negotiation_ref,
          :lower_request_ref,
          :lower_receipt_ref,
          :source_publication_ref,
          :evidence_chain_ref,
          :event_page_ref
        ])
        |> stringify_keys()
        |> Map.merge(%{
          "name" => name,
          "ok" => true,
          "data" => compact_smoke_data(name, data)
        })
      end)

    %{
      "proof_class" => "product_same_run_deterministic",
      "subject_ref" => refs.subject_ref,
      "run_ref" => refs.run_ref,
      "workflow_ref" => refs.workflow_ref,
      "runtime_profile_ref" => refs.runtime_profile_ref,
      "authority_ref" => refs.authority_ref,
      "decision_ref" => refs.decision_ref,
      "connector_manifest_ref" => refs.connector_manifest_ref,
      "capability_negotiation_ref" => refs.capability_negotiation_ref,
      "lower_request_ref" => refs.lower_request_ref,
      "lower_receipt_ref" => refs.lower_receipt_ref,
      "source_publication_ref" => refs.source_publication_ref,
      "evidence_chain_ref" => refs.evidence_chain_ref,
      "event_page_ref" => refs.event_page_ref,
      "all_readbacks_share_refs" => true,
      "steps" => [
        "profile_loaded",
        "source_admitted",
        "scheduled",
        "workflow_start_outbox_queued",
        "current_execution_row_created",
        "mezzanine_runtime_projection_projected",
        "pending_lower_receipt_projected",
        "review_projected",
        "source_previewed",
        "source_published",
        "state_read",
        "queue_read",
        "subject_read",
        "run_read",
        "evidence_read",
        "events_read",
        "leases_issued"
      ],
      "readbacks" => readback_rows
    }
  end

  defp compact_smoke_data("state", _state), do: %{"kind" => "state_snapshot"}
  defp compact_smoke_data("queue", queue), do: %{"total_count" => queue.page.total_count}
  defp compact_smoke_data("reviews", reviews), do: %{"total_count" => reviews.page.total_count}

  defp compact_smoke_data("subject", %{subject: subject}) do
    %{
      "lifecycle_state" => subject.lifecycle_state,
      "title" => subject.title,
      "pending_decision_count" => length(subject.pending_decision_refs || [])
    }
  end

  defp compact_smoke_data("review_decision", result),
    do: %{"status" => to_string(result.status), "action_kind" => result.action_ref.action_kind}

  defp compact_smoke_data("source_preview", preview),
    do: %{"publish_ref" => preview.publish_ref, "operation" => to_string(preview.operation)}

  defp compact_smoke_data("source_publication", publication), do: publication

  defp compact_smoke_data(name, result) when name in ["refresh", "control"] do
    %{
      "status" => to_string(result.status),
      "command_kind" => to_string(result.command_kind),
      "projection_state" => to_string(result.projection_state)
    }
  end

  defp compact_smoke_data(name, lease) when name in ["read_lease", "stream_attach_lease"] do
    sanitized = HeadlessJSON.sanitize(lease)

    %{
      "lease_ref" => get_in(sanitized, ["lease_ref", "id"]),
      "execution_ref" => get_in(sanitized, ["lease_ref", "execution_ref", "id"]),
      "expires_at" => Map.get(sanitized, "expires_at"),
      "scope" => Map.get(sanitized, "scope", %{})
    }
  end

  defp compact_smoke_data("run", %RuntimeRunDetail{} = run),
    do: %{"run_ref" => run.run_ref, "event_count" => length(run.events)}

  defp compact_smoke_data("evidence", evidence),
    do: Map.take(evidence, ["evidence_chain_ref", "run_ref", "subject_ref"])

  defp compact_smoke_data("events", events),
    do: Map.take(events, ["event_page_ref", "run_ref", "page"])

  defp compact_smoke_data(_name, value), do: HeadlessJSON.sanitize(value)

  defp same_run_context(refs, start_result, subject_attrs) do
    %{
      refs: refs,
      start_result: start_result,
      subject_attrs: subject_attrs,
      agent_loop_projection: agent_loop_projection(refs, start_result)
    }
  end

  defp agent_loop_projection(refs, start_result) do
    %{
      subject_ref: refs.subject_ref,
      run_ref: refs.run_ref,
      workflow_ref: refs.workflow_ref,
      status: "waiting_review",
      runtime_events: [
        %{
          event_ref: "event://deterministic-same-run/#{refs.run_ref}/scheduled",
          event_seq: 1,
          event_kind: "scheduler.dispatched",
          observed_at: DateTime.utc_now(),
          subject_ref: refs.subject_ref,
          run_ref: refs.run_ref,
          workflow_ref: refs.workflow_ref,
          payload_ref: "payload://redacted/#{refs.run_ref}/scheduled"
        },
        %{
          event_ref: "event://deterministic-same-run/#{refs.run_ref}/receipt",
          event_seq: 2,
          event_kind: "lower.receipt",
          observed_at: DateTime.utc_now(),
          subject_ref: refs.subject_ref,
          run_ref: refs.run_ref,
          workflow_ref: refs.workflow_ref,
          payload_ref: "payload://redacted/#{refs.run_ref}/receipt"
        }
      ],
      turn_states: [%{"turn_ref" => "turn://deterministic-same-run/#{refs.run_ref}/1"}],
      budget_state: %{"status" => "within_budget"},
      candidate_fact_refs: ["candidate-fact://deterministic-same-run/#{refs.subject_ref}"],
      memory_proof_refs: ["memory-proof://deterministic-same-run/#{refs.run_ref}"],
      action_receipts: [
        %{
          action_id: "codex.session.turn",
          status: "succeeded",
          lower_receipt_ref: refs.lower_receipt_ref
        }
      ],
      runtime_profile_ref: refs.runtime_profile_ref,
      start_payload: HeadlessJSON.sanitize(start_result.payload)
    }
  end

  defp run_request(refs, same_run) do
    %{
      "subject_ref" => refs.subject_ref,
      "state" => "waiting_review",
      "agent_loop_projection" => same_run.agent_loop_projection
    }
  end

  defp review_identity(%{page: %{entries: [review | _]}}) do
    %{
      id: review.decision_ref.id,
      decision_kind: review.decision_ref.decision_kind,
      subject_id: review.subject_ref.id,
      subject_kind: review.subject_ref.subject_kind
    }
  end

  defp source_publication_receipt(refs, preview) do
    %{
      "source_publication_receipt_ref" => refs.source_publication_ref,
      "status" => "previewed",
      "publish_ref" => preview.publish_ref,
      "operation" => to_string(preview.operation),
      "lower_receipt_ref" => refs.lower_receipt_ref,
      "provider_readback_ref" => "provider-readback://pending/#{refs.run_ref}"
    }
  end

  defp start_summary(refs, start_result) do
    %{
      "surface" => to_string(start_result.surface),
      "state" => to_string(start_result.state),
      "subject_ref" => refs.subject_ref,
      "run_ref" => refs.run_ref,
      "workflow_ref" => refs.workflow_ref,
      "runtime_profile_ref" => refs.runtime_profile_ref
    }
  end

  defp readback_opts(product_opts, same_run) do
    Keyword.merge(product_opts, same_run_context: same_run)
  end

  defp product_opts(opts) do
    unique = unique_suffix()

    opts
    |> Map.take([:tenant_id, :pack_version])
    |> Map.put_new(:tenant_id, "extravaganza-smoke-#{unique}")
    |> Map.put_new(:pack_version, "1.0.0-smoke.#{unique}")
    |> Enum.to_list()
  end

  defp linear_subject(opts) do
    issue_id = Map.get(opts, :issue_id) || "SMOKE-#{unique_suffix()}"
    title = Map.get(opts, :title) || "Same-run deterministic smoke #{issue_id}"
    description = Map.get(opts, :description) || "Deterministic same-run headless smoke."

    %{
      external_ref: "linear:#{issue_id}",
      title: title,
      description: description,
      source_kind: "linear",
      payload: %{"issue_id" => issue_id, "identifier" => issue_id, "state" => "Todo"},
      normalized_payload: %{
        "issue_id" => issue_id,
        "identifier" => issue_id,
        "title" => title,
        "description" => description,
        "state" => "Todo",
        "labels" => ["headless", "same-run", "deterministic"]
      }
    }
  end

  defp opts_map(opts) when is_map(opts), do: Map.new(opts)
  defp opts_map(opts) when is_list(opts), do: Map.new(opts)

  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp unique_suffix do
    "#{System.system_time(:microsecond)}-#{System.unique_integer([:positive])}"
  end
end
