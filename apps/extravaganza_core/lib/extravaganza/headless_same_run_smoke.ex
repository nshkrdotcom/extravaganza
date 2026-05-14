defmodule Extravaganza.HeadlessSameRunSmoke do
  @moduledoc false

  alias AppKit.Core.RuntimeReadback.RuntimeRunDetail

  alias Extravaganza.{
    HeadlessCLI,
    HeadlessFixtureBackend,
    HeadlessJSON,
    HeadlessSurface,
    ProductHost,
    SymphonyWorkflowImport
  }

  alias Extravaganza.Presenters.{CommandResultPresenter, RuntimePresenter}

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
    source_publish
    source_publication
    refresh
    control
    read_lease
    stream_attach_lease
    profile
    profile_validate
    profile_reload
    status
    logs
    live_preflight_denial
    command_coverage
    route_coverage
    error_classes
  ]

  defmodule SameRunRuntimeBackend do
    @moduledoc false

    @behaviour AppKit.Core.Backends.RuntimeBackend

    alias AppKit.Core.{RequestContext, SurfaceError}

    alias AppKit.Core.RuntimeSurface.{
      RuntimeLogPage,
      RuntimeProfileApplyResult,
      RuntimeStatusSnapshot
    }

    @impl true
    def apply_runtime_profile(%RequestContext{} = context, runtime_profile, opts) do
      refs = Keyword.fetch!(opts, :same_run_refs)
      run_profile = get_in(runtime_profile, ["work_class", "default_run_profile"]) || %{}

      RuntimeProfileApplyResult.new(%{
        status: :updated,
        tenant_ref: context.tenant_ref.id,
        profile_ref:
          "runtime-profile://same-run/#{Map.get(run_profile, "runtime_profile_ref", "codex_session")}",
        program_ref: "program://#{get_in(runtime_profile, ["program", "slug"]) || "same-run"}",
        policy_bundle_ref:
          "policy-bundle://#{get_in(runtime_profile, ["policy_bundle", "name"]) || "same-run"}",
        work_class_ref:
          "work-class://#{get_in(runtime_profile, ["work_class", "name"]) || "same-run"}",
        placement_profile_ref:
          "placement-profile://#{get_in(runtime_profile, ["placement_profile", "profile_id"]) || "same-run"}",
        metadata: %{
          "proof_class" => "product_same_run_deterministic",
          "subject_ref" => refs.subject_ref,
          "run_ref" => refs.run_ref,
          "workflow_ref" => refs.workflow_ref
        }
      })
    end

    @impl true
    def runtime_status(%RequestContext{} = context, _request, opts) do
      refs = Keyword.fetch!(opts, :same_run_refs)

      RuntimeStatusSnapshot.new(%{
        tenant_ref: context.tenant_ref.id,
        program_ref: "program://same-run",
        health: %{
          "runtime" => "ok",
          "same_run" => %{
            "subject_ref" => refs.subject_ref,
            "run_ref" => refs.run_ref,
            "workflow_ref" => refs.workflow_ref
          }
        },
        preflight: %{
          "profile_import" => "valid",
          "live_provider_dispatch" => "gated"
        },
        metadata: %{
          "proof_class" => "product_same_run_deterministic",
          "runtime_profile_ref" => refs.runtime_profile_ref
        }
      })
    end

    @impl true
    def runtime_logs(%RequestContext{} = context, _request, opts) do
      refs = Keyword.fetch!(opts, :same_run_refs)

      RuntimeLogPage.new(%{
        entries: [
          %{
            ref: "runtime-log://same-run/profile-applied",
            event_kind: "runtime_profile_applied",
            occurred_at: "2026-05-14T00:00:00Z",
            summary: "Same-run runtime profile applied",
            payload: %{
              "tenant_ref" => context.tenant_ref.id,
              "subject_ref" => refs.subject_ref,
              "run_ref" => refs.run_ref
            }
          },
          %{
            ref: "runtime-log://same-run/live-preflight-gated",
            event_kind: "live_provider_preflight.gated",
            occurred_at: "2026-05-14T00:00:01Z",
            summary: "Live provider dispatch stayed gated in deterministic fixture mode",
            payload: %{
              "workflow_ref" => refs.workflow_ref,
              "live_provider_effect?" => false
            }
          }
        ],
        total_count: 2,
        has_more?: false,
        metadata: %{
          "proof_class" => "product_same_run_deterministic",
          "event_page_ref" => refs.event_page_ref
        }
      })
    end

    @impl true
    def record_live_effect(_context, _attrs, _opts), do: not_used_error(:record_live_effect)

    @impl true
    def fetch_github_pr_evidence(_context, _request, _opts),
      do: not_used_error(:fetch_github_pr_evidence)

    @impl true
    def cleanup_github_pr_branch(_context, _request, _opts),
      do: not_used_error(:cleanup_github_pr_branch)

    defp not_used_error(feature) do
      {:ok, error} =
        SurfaceError.new(%{
          code: "not_used_in_same_run",
          message: "Same-run deterministic runtime backend does not dispatch #{feature}",
          kind: :boundary,
          retryable: false,
          details: %{feature: feature}
        })

      {:error, error}
    end
  end

  @spec run(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    opts = opts_map(opts)
    product_opts = product_opts(opts)
    start_opts = Keyword.put(product_opts, :deterministic_lower_lane?, true)
    subject_attrs = linear_subject(opts)

    with {:ok, start_result} <- ProductHost.start_run(subject_attrs, start_opts),
         {:ok, runtime_projection} <-
           ProductHost.runtime_projection(start_result.payload.work_object_id, product_opts),
         {:ok, refs} <- refs_from_start(start_result, runtime_projection) do
      same_run = same_run_context(refs, start_result, subject_attrs, runtime_projection)
      readback_opts = readback_opts(product_opts, same_run)
      source_opts = source_surface_opts(product_opts)
      workflow_opts = workflow_import_opts(refs)
      runtime_opts = runtime_surface_opts(product_opts, refs)

      with {:ok, state} <- ProductHost.state_snapshot(%{}, product_opts),
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
           {:ok, source_publish} <-
             HeadlessSurface.publish_linear_source(source_publish_attrs(refs), source_opts),
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
             ProductHost.issue_stream_attach_lease(refs.subject_ref, readback_opts),
           {:ok, profile} <- SymphonyWorkflowImport.profile(workflow_opts),
           {:ok, profile_validate} <- profile_validate(workflow_opts),
           {:ok, profile_reload} <- profile_reload(workflow_opts, runtime_opts),
           {:ok, status} <- HeadlessSurface.runtime_status(runtime_request(refs), runtime_opts),
           {:ok, logs} <- HeadlessSurface.runtime_logs(runtime_request(refs), runtime_opts) do
        live_preflight_denial = live_preflight_denial()
        command_coverage = command_coverage()
        route_coverage = route_coverage()
        error_classes = error_classes()

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
            source_publish: source_publish,
            source_publication: source_publication_receipt(refs, source_preview),
            refresh: refresh,
            control: control,
            read_lease: read_lease,
            stream_attach_lease: stream_attach_lease,
            profile: profile,
            profile_validate: profile_validate,
            profile_reload: profile_reload,
            status: status,
            logs: logs,
            live_preflight_denial: live_preflight_denial,
            command_coverage: command_coverage,
            route_coverage: route_coverage,
            error_classes: error_classes
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

  defp refs_from_start(start_result, runtime_projection) do
    payload = start_result.payload
    run_ref = Map.fetch!(payload, :run_ref)
    metadata = run_ref.metadata || %{}
    subject_ref = Map.fetch!(payload, :work_object_id)
    workflow_ref = Map.fetch!(payload, :workflow_start_ref)
    execution_id = Map.fetch!(payload, :execution_id)
    lower_receipt = first_lower_receipt!(runtime_projection)
    lower_metadata = lower_receipt.metadata || %{}
    runtime_metadata = runtime_projection.runtime.metadata || %{}
    lower_envelope = lower_envelope(lower_metadata, runtime_metadata)
    governance = Map.get(runtime_metadata, "governance", %{})
    source_publication = source_publication(lower_metadata, runtime_metadata)

    {:ok,
     %{
       subject_ref: subject_ref,
       run_ref: run_ref.run_id,
       workflow_ref: workflow_ref,
       runtime_profile_ref: Map.get(metadata, :runtime_profile_ref),
       authority_ref: required_projected_ref(governance, lower_metadata, "authority_ref"),
       decision_ref:
         Map.get(governance, "authority_decision_hash") ||
           get_in(lower_metadata, ["authority_decision", "authority_decision_hash"]),
       connector_manifest_ref:
         first_ref(Map.get(governance, "connector_manifest_refs")) ||
           Map.get(lower_envelope, "connector_manifest_ref"),
       capability_negotiation_ref:
         first_ref(Map.get(governance, "capability_negotiation_refs")) ||
           Map.get(lower_envelope, "capability_negotiation_ref"),
       lower_request_ref: Map.fetch!(lower_envelope, "lower_request_ref"),
       lower_receipt_ref: lower_receipt.lower_receipt_ref,
       source_publication_ref: Map.fetch!(source_publication, "source_publication_receipt_ref"),
       source_publication: source_publication,
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
        "deterministic_authority_projected",
        "deterministic_lower_projected",
        "deterministic_receipt_projected",
        "review_projected",
        "source_previewed",
        "source_published",
        "profile_imported",
        "profile_validated",
        "profile_reloaded",
        "state_read",
        "queue_read",
        "subject_read",
        "run_read",
        "evidence_read",
        "events_read",
        "runtime_status_read",
        "runtime_logs_read",
        "live_provider_preflight_denied",
        "command_route_matrix_recorded",
        "error_classes_recorded",
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

  defp compact_smoke_data("source_publish", result) do
    sanitized = HeadlessJSON.sanitize(result)
    receipt = Map.get(sanitized, "source_publication_receipt", %{})

    %{
      "status" => Map.get(receipt, "status"),
      "source_publication_ref" => Map.get(receipt, "source_publication_receipt_ref"),
      "source_binding_id" => Map.get(receipt, "source_binding_id"),
      "provider_request_sent?" => Map.get(sanitized, "provider_request_sent?"),
      "provider_response_received?" => Map.get(sanitized, "provider_response_received?"),
      "credential_redeemed?" => Map.get(sanitized, "credential_redeemed?")
    }
  end

  defp compact_smoke_data("source_publication", publication), do: publication

  defp compact_smoke_data("profile", profile) do
    %{
      "source" => Map.get(profile, "source"),
      "validation_status" => get_in(profile, ["validation", "status"]),
      "api_key_supplied?" => get_in(profile, ["config", "tracker", "api_key_supplied?"]),
      "prompt_hash" => get_in(profile, ["workflow", "prompt_hash"])
    }
  end

  defp compact_smoke_data("profile_validate", result) do
    %{
      "status" => Map.get(result, "status"),
      "prompt_hash" => get_in(result, ["profile", "workflow", "prompt_hash"])
    }
  end

  defp compact_smoke_data("profile_reload", result) do
    %{
      "status" => Map.get(result, "status"),
      "last_known_good_status" => get_in(result, ["last_known_good", "status"]),
      "runtime_profile_ref" => Map.get(result, "runtime_profile_ref"),
      "runtime_profile_apply_status" => get_in(result, ["runtime_profile_apply", "status"])
    }
  end

  defp compact_smoke_data("status", status) do
    status
    |> RuntimePresenter.present_status()
    |> Map.take(["schema_ref", "schema_version", "data"])
  end

  defp compact_smoke_data("logs", logs) do
    logs
    |> RuntimePresenter.present_logs()
    |> Map.take(["schema_ref", "schema_version", "data"])
  end

  defp compact_smoke_data("live_preflight_denial", result), do: result
  defp compact_smoke_data("command_coverage", result), do: result
  defp compact_smoke_data("route_coverage", result), do: result
  defp compact_smoke_data("error_classes", result), do: result

  defp compact_smoke_data(name, result) when name in ["refresh", "control"] do
    data =
      result
      |> CommandResultPresenter.present()
      |> Map.fetch!("data")

    %{
      "status" => to_string(Map.get(data, "status")),
      "command_kind" => to_string(Map.get(data, "command_kind")),
      "projection_state" =>
        to_string(Map.get(data, "projection_state") || Map.get(data, "workflow_effect_state"))
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

  defp same_run_context(refs, start_result, subject_attrs, runtime_projection) do
    %{
      refs: refs,
      start_result: start_result,
      subject_attrs: subject_attrs,
      runtime_projection: runtime_projection,
      agent_loop_projection: agent_loop_projection(refs, start_result, runtime_projection)
    }
  end

  defp agent_loop_projection(refs, start_result, runtime_projection) do
    %{
      subject_ref: refs.subject_ref,
      run_ref: refs.run_ref,
      workflow_ref: refs.workflow_ref,
      status: "waiting_review",
      runtime_events: runtime_events(refs, runtime_projection),
      turn_states: [%{"turn_ref" => "turn://deterministic-same-run/#{refs.run_ref}/1"}],
      budget_state: %{
        "status" => "within_budget",
        "token_totals" => runtime_projection.runtime.token_totals
      },
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
    refs.source_publication
    |> Map.merge(%{
      "publish_ref" => preview.publish_ref,
      "operation" => to_string(preview.operation),
      "lower_receipt_ref" => refs.lower_receipt_ref
    })
  end

  defp first_lower_receipt!(runtime_projection) do
    case runtime_projection.lower_receipts do
      [receipt | _] ->
        if String.contains?(receipt.lower_receipt_ref || "", "/pending/") do
          raise KeyError, key: :lower_receipt_ref, term: receipt
        else
          receipt
        end

      _other ->
        raise KeyError, key: :lower_receipts, term: runtime_projection
    end
  end

  defp lower_envelope(lower_metadata, runtime_metadata) do
    Map.get(runtime_metadata, "lower_envelope") ||
      Map.get(lower_metadata, "governed_lower_envelope") ||
      Map.get(lower_metadata, "lower_envelope") ||
      %{}
  end

  defp source_publication(lower_metadata, runtime_metadata) do
    Map.get(runtime_metadata, "source_publication") ||
      Map.get(lower_metadata, "source_publication") ||
      %{}
  end

  defp required_projected_ref(governance, lower_metadata, key) do
    Map.get(governance, key) ||
      get_in(lower_metadata, ["authority_decision", key]) ||
      raise(KeyError, key: key, term: %{governance: governance, lower_metadata: lower_metadata})
  end

  defp first_ref([ref | _]), do: ref
  defp first_ref(_value), do: nil

  defp runtime_events(refs, runtime_projection) do
    runtime_projection.runtime.events
    |> Enum.with_index(1)
    |> Enum.map(fn {event, seq} ->
      %{
        event_ref: "event://deterministic-same-run/#{refs.run_ref}/#{event.event_kind}",
        event_seq: seq,
        event_kind: event.event_kind,
        observed_at: DateTime.utc_now(),
        subject_ref: refs.subject_ref,
        run_ref: refs.run_ref,
        workflow_ref: refs.workflow_ref,
        payload_ref: "payload://redacted/#{refs.run_ref}/#{event.event_kind}",
        count: event.count
      }
    end)
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

  defp source_surface_opts(product_opts) do
    product_opts
    |> Keyword.take([:tenant_id, :pack_version])
    |> Keyword.put(:source_backend, HeadlessFixtureBackend)
  end

  defp runtime_surface_opts(product_opts, refs) do
    product_opts
    |> Keyword.take([:tenant_id, :pack_version])
    |> Keyword.put(:backend, SameRunRuntimeBackend)
    |> Keyword.put(:same_run_refs, refs)
  end

  defp workflow_import_opts(refs) do
    root =
      Path.join(System.tmp_dir!(), "extravaganza-same-run-#{safe_ref_fragment(refs.run_ref)}")

    workflow_path = Path.join(root, "WORKFLOW.md")

    File.mkdir_p!(root)
    File.write!(workflow_path, workflow_content(refs))

    [
      workflow_path: workflow_path,
      cwd: root,
      profile_cache_path: Path.join(root, "last-good-profile.json"),
      env: %{
        "LINEAR_API_KEY" => "same-run-linear-key",
        "LINEAR_ASSIGNEE" => "same-run-assignee"
      }
    ]
  end

  defp workflow_content(refs) do
    """
    ---
    tracker:
      kind: linear
      api_key: "$LINEAR_API_KEY"
      project_slug: same-run
      assignee: "$LINEAR_ASSIGNEE"
      active_states: ["Todo", "In Progress"]
      terminal_states: ["Done"]
    polling:
      interval_ms: 15000
    workspace:
      root: "./workspace"
    worker:
      ssh_hosts: []
    server:
      host: "127.0.0.1"
      port: 4001
    ---
    Work on {{ issue.identifier }} for #{refs.run_ref}
    """
  end

  defp profile_validate(workflow_opts) do
    with {:ok, profile} <- SymphonyWorkflowImport.profile(workflow_opts) do
      case profile["validation"] do
        %{"status" => "valid"} ->
          {:ok, %{"status" => "valid", "profile" => profile}}

        %{"reason" => %{"code" => code, "value" => value}} ->
          {:error, {code, value}}

        %{"reason" => reason} ->
          {:error, reason}
      end
    end
  end

  defp profile_reload(workflow_opts, runtime_opts) do
    with {:ok, reload} <- SymphonyWorkflowImport.reload(workflow_opts) do
      apply_runtime_profile_to_reload(reload, runtime_opts)
    end
  end

  defp apply_runtime_profile_to_reload(
         %{"status" => "reloaded", "profile" => %{"app_kit_runtime_profile" => runtime_profile}} =
           reload,
         runtime_opts
       ) do
    with {:ok, apply_result} <-
           HeadlessSurface.apply_runtime_profile(runtime_profile, runtime_opts) do
      apply_readback = RuntimePresenter.present_profile_apply(apply_result)

      {:ok,
       reload
       |> Map.put("runtime_profile_apply", apply_readback)
       |> Map.put("runtime_profile_ref", apply_readback["profile_ref"])}
    end
  end

  defp apply_runtime_profile_to_reload(reload, _runtime_opts), do: {:ok, reload}

  defp runtime_request(refs) do
    %{
      "subject_id" => refs.subject_ref,
      "run_id" => refs.run_ref,
      "trace_id" => refs.trace_id
    }
  end

  defp source_publish_attrs(refs) do
    %{
      subject_ref: refs.subject_ref,
      source_binding_id: "linear-primary",
      source_ref: "linear://same-run/#{refs.subject_ref}",
      issue_id: "SMOKE-SAME-RUN",
      effect: "comment",
      idempotency_key: "same-run-source-publish:#{refs.run_ref}",
      message: "Same-run deterministic source publication"
    }
  end

  defp live_preflight_denial do
    examples =
      [
        {"live.linear-source", :live_linear_source_example},
        {"live.linear-current-states", :live_linear_current_states_example},
        {"live.codex-turn", :live_codex_turn_example},
        {"live.linear-publication", :live_linear_publication_example},
        {"live.linear-graphql-tool", :live_linear_graphql_tool_example},
        {"live.github-evidence", :live_github_evidence_example},
        {"live.github-pr-cleanup", :live_github_pr_cleanup_example}
      ]
      |> Enum.map(fn {operation, callback} ->
        opts = [
          fixture: "headless_live",
          credential_available?: true,
          confirm_close?: true,
          trace_id: "trace:same-run-live-preflight:#{operation}"
        ]

        {:ok, result} = apply(ProductHost, callback, [opts])
        provider_effect = Map.get(result, "provider_effect", %{})
        skip_reason = Map.get(provider_effect, "skip_reason", %{})

        %{
          "operation" => operation,
          "status" => Map.get(result, "status"),
          "provider" => Map.get(result, "provider"),
          "skip_reason_code" => Map.get(skip_reason, "code"),
          "live_provider_effect?" => Map.get(result, "live_provider_effect?")
        }
      end)

    %{
      "examples" => examples,
      "all_live_provider_effects_gated?" =>
        Enum.all?(examples, &(&1["skip_reason_code"] == "live_product_path_required"))
    }
  end

  defp command_coverage do
    operations = Enum.map(HeadlessCLI.operations(), &Atom.to_string/1)

    %{
      "fixture_mode" => "deterministic_same_run",
      "operations" => operations,
      "total_count" => length(operations)
    }
  end

  defp route_coverage do
    routes = [
      route("GET", "/api/v1/state", :state),
      route("GET", "/api/v1/status", :status),
      route("GET", "/api/v1/logs", :logs),
      route("GET", "/api/v1/profile", :profile),
      route("GET", "/api/v1/subjects/:subject_id", :subject),
      route("GET", "/api/v1/subjects/:subject_id/source-publication", :source_publication),
      route("GET", "/api/v1/runs/:run_id", :run),
      route("GET", "/api/v1/runs/:run_id/evidence", :evidence),
      route("GET", "/api/v1/events", :events),
      route("GET", "/api/v1/reviews", :reviews),
      route("GET", "/api/v1/:issue_identifier", :issue_subject),
      route("POST", "/api/v1/profile/validate", :profile_validate),
      route("POST", "/api/v1/profile/reload", :profile_reload),
      route("POST", "/api/v1/source-publication", :source_publish),
      route("POST", "/api/v1/subjects/:subject_id/source-publication", :source_publish),
      route("POST", "/api/v1/refresh", :refresh),
      route("POST", "/api/v1/subjects/:subject_id/actions/:action", :control),
      route("POST", "/api/v1/subjects/:subject_id/control/:action", :control),
      route("POST", "/api/v1/subjects/:subject_id/read-lease", :read_lease),
      route("POST", "/api/v1/subjects/:subject_id/stream-attach-lease", :stream_attach_lease),
      route("POST", "/api/v1/reviews/:decision_id/decisions/:decision", :review_decision),
      route("*", "/api/v1/*path", :not_found)
    ]

    %{"routes" => routes, "total_count" => length(routes)}
  end

  defp route(method, path, operation) do
    %{"method" => method, "path" => path, "operation" => Atom.to_string(operation)}
  end

  defp error_classes do
    reasons = [
      :bad_request,
      :not_found,
      :method_not_allowed,
      :invalid_action,
      :action_denied,
      :unauthorized_lower_read,
      :snapshot_timeout,
      :runtime_projection_not_found,
      :unavailable,
      :archived,
      :live_product_path_required,
      {:invalid_workflow_config, "runtime profile mismatch"},
      %{
        "code" => "credential_not_supplied_to_product_command",
        "credential_refs" => ["LINEAR_API_KEY"]
      },
      %AppKit.Core.SurfaceError{
        code: "provider_denied",
        message: "provider authority denied the request",
        kind: :authorization,
        retryable: false,
        details: %{lower_denial_ref: "lower-denial://same-run/provider"}
      },
      %AppKit.Core.SurfaceError{
        code: "provider_failed",
        message: "provider failed after dispatch",
        kind: :transient,
        retryable: true,
        details: %{provider_request_ref: "provider-request://same-run/provider"}
      },
      {:live_surface_dependency_failed, :req, {:not_started, :ssl}},
      :runtime_installation_not_provisioned,
      :internal_error
    ]

    errors =
      Enum.map(reasons, fn reason ->
        :headless_api
        |> HeadlessJSON.error(reason, generated_at: "2026-05-14T00:00:00Z")
        |> Map.fetch!("error")
        |> Map.take(["code", "class", "retryable", "missing_refs"])
      end)

    %{"errors" => errors, "total_count" => length(errors)}
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

  defp safe_ref_fragment(ref) do
    Regex.replace(~r/[^A-Za-z0-9._-]/, to_string(ref), "-")
  end

  defp unique_suffix do
    "#{System.system_time(:microsecond)}-#{System.unique_integer([:positive])}"
  end
end
