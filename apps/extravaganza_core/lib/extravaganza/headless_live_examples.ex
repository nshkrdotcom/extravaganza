defmodule Extravaganza.HeadlessLiveExamples do
  @moduledoc false

  alias AppKit.Core.AgentIntake.RunOutcomeFuture
  alias AppKit.Core.RuntimeReadback.RuntimeRunDetail
  alias AppKit.HeadlessSurface, as: AppKitHeadlessSurface
  alias Extravaganza.{GitHubPrBranchCleanupReceipt, GitHubPrEvidenceReceipt}

  alias Extravaganza.{
    AppKitContext,
    CodingOpsTemplates,
    Config,
    HeadlessFixtureBackend,
    HeadlessSurface,
    ProductHost,
    ProductPack,
    RouteEvidence
  }

  @provider_examples %{
    linear_source: %{
      operation: "live.linear-source",
      provider: "linear",
      command: "mix extravaganza.headless.live.linear_source --json",
      product_entrypoint: "Extravaganza.ProductHost.live_linear_source_example",
      credential_refs: ["LINEAR_API_KEY"],
      capability_ids: ["linear.users.get_self", "linear.issues.list", "linear.issues.retrieve"],
      provider_effect: "source_intake"
    },
    linear_current_states: %{
      operation: "live.linear-current-states",
      provider: "linear",
      command: "mix extravaganza.headless.live.linear_current_states --json",
      product_entrypoint: "Extravaganza.ProductHost.live_linear_current_states_example",
      credential_refs: ["LINEAR_API_KEY"],
      capability_ids: ["linear.users.get_self", "linear.issues.list"],
      provider_effect: "source_current_state"
    },
    codex_turn: %{
      operation: "live.codex-turn",
      provider: "codex",
      command: "mix extravaganza.headless.live.codex_turn --json",
      product_entrypoint: "Extravaganza.ProductHost.live_codex_turn_example",
      credential_refs: ["OPENAI_API_KEY", "CODEX_API_KEY"],
      capability_ids: ["codex.session.turn"],
      provider_effect: "agent_turn"
    },
    linear_publication: %{
      operation: "live.linear-publication",
      provider: "linear",
      command: "mix extravaganza.headless.live.linear_publication --json",
      product_entrypoint: "Extravaganza.ProductHost.live_linear_publication_example",
      credential_refs: ["LINEAR_API_KEY"],
      capability_ids: [
        "linear.comments.update",
        "linear.comments.create",
        "linear.issues.update",
        "linear.workflow_states.list"
      ],
      provider_effect: "source_publication"
    },
    linear_graphql_tool: %{
      operation: "live.linear-graphql-tool",
      provider: "linear",
      command: "mix extravaganza.headless.live.linear_graphql_tool --json",
      product_entrypoint: "Extravaganza.ProductHost.live_linear_graphql_tool_example",
      credential_refs: ["LINEAR_API_KEY"],
      capability_ids: ["linear.graphql.execute"],
      provider_effect: "dynamic_tool"
    },
    github_evidence: %{
      operation: "live.github-evidence",
      provider: "github",
      command: "mix extravaganza.headless.live.github_evidence --json",
      product_entrypoint: "Extravaganza.ProductHost.live_github_evidence_example",
      credential_refs: ["GH_TOKEN", "GITHUB_TOKEN"],
      capability_ids: [
        "github.pr.fetch",
        "github.pr.reviews.list",
        "github.pr.review_comments.list",
        "github.commit.statuses.get_combined",
        "github.check_runs.list_for_ref"
      ],
      provider_effect: "github_pr_evidence"
    },
    github_pr_cleanup: %{
      operation: "live.github-pr-cleanup",
      provider: "github",
      command: "mix extravaganza.headless.live.github_pr_cleanup --json",
      product_entrypoint: "Extravaganza.ProductHost.live_github_pr_cleanup_example",
      credential_refs: ["GH_TOKEN", "GITHUB_TOKEN"],
      capability_ids: ["github.pr.list", "github.comment.create", "github.pr.update"],
      provider_effect: "github_pr_branch_cleanup"
    }
  }

  @example_order [
    :linear_source,
    :linear_current_states,
    :codex_turn,
    :linear_publication,
    :linear_graphql_tool,
    :github_evidence
  ]

  @standalone_examples @example_order ++ [:github_pr_cleanup]

  @memory_tracker_callbacks [
    "fetch_candidate_issues",
    "fetch_issues_by_states",
    "fetch_issue_states_by_ids",
    "create_comment",
    "update_issue_state"
  ]

  @authority_effect_keys [
    :authority_authorized?,
    :authority_handoff_ref,
    :authority_packet_ref,
    :connector_binding_ref,
    :credential_lease_ref,
    :authority_raw_material_present?,
    :authorized?,
    :handoff_ref,
    :raw_material_present?
  ]

  @spec run(atom(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def run(kind, opts \\ [])

  def run(:smoke, opts) do
    opts = opts_map(opts)
    trace_id = live_trace_id(opts, "live.smoke")

    with {:ok, proof} <- product_proof(opts) do
      examples =
        @example_order
        |> Enum.map(fn kind ->
          example = example!(kind)
          {example.operation, example_payload(kind, example, proof, opts)}
        end)
        |> Map.new()

      summary = aggregate_summary(examples)

      data =
        proof
        |> common_refs()
        |> Map.delete("source_publication_ref")
        |> Map.merge(%{
          "status" => aggregate_status(summary),
          "operation" => "live.smoke",
          "trace_id" => trace_id,
          "correlation_ref" => live_smoke_correlation_ref(trace_id),
          "receipt_ref" => live_receipt_ref("live.smoke", proof),
          "receipt_state" => "recorded",
          "product_path_exercised?" => true,
          "product_readback_confirmed?" => product_readback_confirmed?(proof),
          "product_path" => product_path(proof, "Extravaganza.ProductHost.live_smoke"),
          "route_evidence" => RouteEvidence.from_live_smoke(examples, %{trace_ref: trace_id}),
          "examples" => examples,
          "deterministic_memory_tracker_matrix" => deterministic_memory_tracker_matrix(opts)
        })
        |> Map.merge(example_mode_fields(opts, summary))
        |> maybe_put("source_publication_ref", aggregate_source_publication_ref(examples))
        |> Map.merge(summary)

      {:ok, data}
    end
  end

  def run(kind, opts) when kind in @standalone_examples do
    opts = opts_map(opts)
    example = example!(kind)

    with {:ok, proof} <- product_proof(opts) do
      {:ok, example_payload(kind, example, proof, opts)}
    end
  end

  defp example_payload(kind, example, proof, opts) do
    provider_effect = provider_effect(kind, example, proof, opts)
    credential_preflight = credential_preflight(kind, example, opts)

    payload =
      proof
      |> common_refs()
      |> provider_effect_refs(provider_effect)
      |> Map.merge(%{
        "status" => example_status(provider_effect),
        "operation" => example.operation,
        "trace_id" => live_trace_id(opts, example.operation),
        "receipt_ref" => live_receipt_ref(example.operation, proof),
        "receipt_state" => "recorded",
        "provider" => example.provider,
        "capability_ids" => example.capability_ids,
        "credential_refs" => example.credential_refs,
        "credential_preflight" => credential_preflight,
        "command" => example.command,
        "product_path_exercised?" => true,
        "product_path" => product_path(proof, example.product_entrypoint, provider_effect),
        "route_evidence" => Map.get(provider_effect, "route_evidence"),
        "provider_effect" => provider_effect
      })
      |> Map.merge(example_mode_fields(opts, provider_effect))

    payload
    |> maybe_put("source_publication_ref", Map.get(provider_effect, "source_publication_ref"))
    |> maybe_put("lower_request_ref", Map.get(provider_effect, "lower_request_ref"))
    |> maybe_put("lower_receipt_ref", Map.get(provider_effect, "lower_receipt_ref"))
  end

  defp provider_effect(kind, example, proof, opts) do
    kind
    |> provider_effect_for(example, proof, opts)
    |> annotate_provider_effect(opts)
    |> RouteEvidence.put_operation_receipts()
    |> put_route_evidence(kind, example, proof, opts)
  end

  defp put_route_evidence(provider_effect, kind, example, proof, opts) do
    trace_ref = live_trace_id(opts, example.operation)

    Map.put(
      provider_effect,
      "route_evidence",
      RouteEvidence.from_provider_effect(kind, example, proof, provider_effect, %{
        trace_ref: trace_ref
      })
    )
  end

  defp provider_effect_for(kind, example, proof, opts) do
    if provider_effect_skipped?(kind, opts) do
      skipped_effect(kind, example, opts)
    else
      dispatch_provider_effect(kind, example, proof, opts)
    end
  end

  defp dispatch_provider_effect(:linear_source, example, proof, opts),
    do: linear_source_effect(example, proof, opts)

  defp dispatch_provider_effect(:linear_current_states, example, proof, opts),
    do: linear_current_states_effect(example, proof, opts)

  defp dispatch_provider_effect(:linear_publication, example, proof, opts),
    do: linear_publication_effect(example, proof, opts)

  defp dispatch_provider_effect(:linear_graphql_tool, example, proof, opts),
    do: linear_graphql_tool_effect(example, proof, opts)

  defp dispatch_provider_effect(:codex_turn, example, proof, opts),
    do: codex_turn_effect(example, proof, opts)

  defp dispatch_provider_effect(:github_evidence, example, proof, opts),
    do: github_evidence_effect(example, proof, opts)

  defp dispatch_provider_effect(:github_pr_cleanup, example, proof, opts),
    do: github_pr_cleanup_effect(example, proof, opts)

  defp dispatch_provider_effect(kind, example, _proof, opts),
    do: skipped_effect(kind, example, opts)

  defp provider_effect_skipped?(kind, opts) do
    not credential_supplied?(kind, opts) or
      (not live_product_path?(opts) and credential_supplied?(kind, opts))
  end

  defp skipped_effect(kind, example, opts) do
    %{
      "provider" => example.provider,
      "effect" => example.provider_effect,
      "capability_ids" => example.capability_ids,
      "status" => "skipped",
      "skip_reason" => skip_reason(kind, example, opts),
      "credential_preflight" => credential_preflight(kind, example, opts)
    }
  end

  defp linear_source_effect(example, proof, opts) do
    case HeadlessSurface.fetch_source_candidates(linear_source_binding(opts), surface_opts(opts)) do
      {:ok, result} ->
        %{
          "provider" => example.provider,
          "effect" => example.provider_effect,
          "capability_ids" => example.capability_ids,
          "status" => "receipt_recorded",
          "operation" => source_intake_operation(result) || "linear.issues.list",
          "source_binding_id" => value(result, :source_binding_id) || "linear-primary",
          "subject_count" => source_subject_count(result),
          "credential_present?" => true,
          "credential_redeemed?" => truthy?(value(result, :credential_redeemed?)),
          "provider_request_sent?" => truthy?(value(result, :provider_request_sent?)),
          "provider_response_received?" => truthy?(value(result, :provider_response_received?)),
          "receipt_recorded?" => true,
          "product_readback_confirmed?" => product_readback_confirmed?(proof),
          "appkit_surfaces" => ["AppKit.SourceSurface", "AppKit.HeadlessSurface"],
          "source_state_names" => source_state_names(opts),
          "project_slug" => string_value(opts, :project_slug),
          "team_id" => string_value(opts, :team_id),
          "assignee" => linear_source_assignee_label(opts),
          "subjects" => source_subjects(result),
          "viewer_preflight?" => present?(value(result, :viewer_resolution)),
          "viewer_operation" => viewer_operation(result),
          "viewer_provider_request_sent?" =>
            truthy?(result |> value(:viewer_resolution) |> value(:provider_request_sent?)),
          "viewer_provider_response_received?" =>
            truthy?(result |> value(:viewer_resolution) |> value(:provider_response_received?)),
          "viewer_lower_request_ref" =>
            result |> value(:viewer_resolution) |> value(:lower_request_ref),
          "viewer_lower_receipt_ref" =>
            result |> value(:viewer_resolution) |> value(:lower_receipt_ref),
          "lower_request_ref" => value(result, :lower_request_ref),
          "lower_receipt_ref" => value(result, :lower_receipt_ref)
        }
        |> Map.merge(authority_effect_fields(result))
        |> compact_map()

      {:error, reason} ->
        failed_effect(example, reason)
    end
  end

  defp linear_current_states_effect(example, proof, opts) do
    with {:ok, issue_ids} <- current_state_issue_ids(opts),
         {:ok, result} <-
           HeadlessSurface.current_source_states(
             issue_ids,
             linear_source_binding(opts),
             surface_opts(opts)
           ) do
      current_state = value(result, :source_current_state) || %{}

      %{
        "provider" => example.provider,
        "effect" => example.provider_effect,
        "capability_ids" => example.capability_ids,
        "status" => "receipt_recorded",
        "operation" => value(current_state, :operation) || "linear.issues.list",
        "source_binding_id" => value(current_state, :source_binding_id) || "linear-primary",
        "requested_issue_ids" => value(result, :requested_issue_ids) || issue_ids,
        "missing_issue_ids" => value(current_state, :missing_issue_ids) || [],
        "current_state_count" => current_state_count(result),
        "credential_present?" => true,
        "credential_redeemed?" => truthy?(value(result, :credential_redeemed?)),
        "provider_request_sent?" => truthy?(value(result, :provider_request_sent?)),
        "provider_response_received?" => truthy?(value(result, :provider_response_received?)),
        "receipt_recorded?" => present?(value(result, :lower_receipt_ref)),
        "product_readback_confirmed?" => product_readback_confirmed?(proof),
        "appkit_surfaces" => ["AppKit.SourceSurface", "AppKit.HeadlessSurface"],
        "viewer_preflight?" => present?(value(result, :viewer_resolution)),
        "viewer_operation" => viewer_operation(result),
        "viewer_provider_request_sent?" =>
          truthy?(result |> value(:viewer_resolution) |> value(:provider_request_sent?)),
        "viewer_provider_response_received?" =>
          truthy?(result |> value(:viewer_resolution) |> value(:provider_response_received?)),
        "viewer_lower_request_ref" =>
          result |> value(:viewer_resolution) |> value(:lower_request_ref),
        "viewer_lower_receipt_ref" =>
          result |> value(:viewer_resolution) |> value(:lower_receipt_ref),
        "lower_request_ref" => value(result, :lower_request_ref),
        "lower_receipt_ref" => value(result, :lower_receipt_ref)
      }
      |> Map.merge(authority_effect_fields([current_state, result]))
      |> compact_map()
    else
      {:error, reason} ->
        failed_effect(example, reason)
    end
  end

  defp linear_publication_effect(example, proof, opts) do
    case linear_publication_attrs(opts) do
      {:ok, attrs} ->
        case HeadlessSurface.publish_source_update(attrs, surface_opts(opts)) do
          {:ok, result} ->
            receipt = value(result, :source_publication_receipt) || result
            denial? = source_publication_denial?(receipt)

            %{
              "provider" => example.provider,
              "effect" => example.provider_effect,
              "capability_ids" => example.capability_ids,
              "status" => source_publication_effect_status(receipt),
              "operation" => value(receipt, :capability_id) || "linear.comments.create",
              "source_binding_id" => value(receipt, :source_binding_id) || "linear-primary",
              "source_publication_ref" => source_publication_ref(receipt, denial?),
              "credential_present?" => true,
              "credential_redeemed?" => truthy?(value(result, :credential_redeemed?)),
              "provider_request_sent?" => truthy?(value(result, :provider_request_sent?)),
              "provider_response_received?" =>
                truthy?(value(result, :provider_response_received?)),
              "receipt_recorded?" => not denial?,
              "product_readback_confirmed?" => product_readback_confirmed?(proof),
              "lower_request_ref" => value(receipt, :lower_request_ref),
              "lower_receipt_ref" => value(receipt, :lower_receipt_ref),
              "lower_denial_ref" =>
                value(receipt, :lower_denial_ref) || value(result, :lower_denial_ref),
              "denial_class" => value(receipt, :denial_class),
              "denial_reason" => value(receipt, :denial_reason),
              "dry_run?" => value(receipt, :status) == "dry_run_denied",
              "workpad_refs" => value(receipt, :workpad_refs),
              "comment_ref" => value(receipt, :comment_ref),
              "fallback_from" => value(receipt, :fallback_from),
              "issue_id" => value(receipt, :issue_id),
              "state_id" => value(receipt, :state_id),
              "state_name" => value(receipt, :state_name),
              "state_lookup_lower_request_ref" => value(receipt, :state_lookup_lower_request_ref),
              "state_lookup_lower_receipt_ref" => value(receipt, :state_lookup_lower_receipt_ref),
              "state_update?" => value(receipt, :capability_id) == "linear.issues.update"
            }
            |> Map.merge(authority_effect_fields([receipt, result]))
            |> compact_map()

          {:error, reason} ->
            failed_effect(example, reason)
        end

      {:error, reason} ->
        failed_effect(example, reason)
    end
  end

  defp linear_graphql_tool_effect(example, proof, opts) do
    case linear_graphql_tool_request(opts) do
      {:ok, attrs} ->
        case HeadlessSurface.execute_issue_tracker_query_tool(attrs, surface_opts(opts)) do
          {:ok, result} ->
            success? = truthy?(value(result, :success?))
            lower_receipt_ref = value(result, :lower_receipt_ref)

            %{
              "provider" => example.provider,
              "effect" => example.provider_effect,
              "capability_ids" => example.capability_ids,
              "status" => if(success?, do: "receipt_recorded", else: "failed"),
              "operation" => value(result, :operation) || "linear.graphql.execute",
              "tool_name" => value(result, :tool_name) || "linear_graphql",
              "dynamic_tool_response" => value(result, :dynamic_tool_response),
              "credential_present?" => true,
              "credential_redeemed?" => truthy?(value(result, :credential_redeemed?)),
              "provider_request_sent?" => truthy?(value(result, :provider_request_sent?)),
              "provider_response_received?" =>
                truthy?(value(result, :provider_response_received?)),
              "receipt_recorded?" => success? and present?(lower_receipt_ref),
              "product_readback_confirmed?" => product_readback_confirmed?(proof),
              "appkit_surfaces" => ["AppKit.RuntimeGateway", "AppKit.HeadlessSurface"],
              "lower_request_ref" => value(result, :lower_request_ref),
              "lower_receipt_ref" => lower_receipt_ref
            }
            |> Map.merge(authority_effect_fields(result))
            |> compact_map()

          {:error, reason} ->
            failed_effect(example, reason)
        end

      {:error, reason} ->
        failed_effect(example, reason)
    end
  end

  defp deterministic_memory_tracker_matrix(opts) do
    source_binding = memory_tracker_source_binding()
    states_binding = memory_tracker_source_binding(["Todo"])
    matrix_opts = memory_tracker_fixture_opts(opts)

    with {:ok, candidates} <- HeadlessSurface.fetch_source_candidates(source_binding, matrix_opts),
         {:ok, state_candidates} <-
           HeadlessSurface.fetch_source_candidates(states_binding, matrix_opts),
         {:ok, current_states} <-
           HeadlessSurface.current_source_states(
             ["lin-issue-321"],
             source_binding,
             matrix_opts
           ),
         {:ok, comment_create} <-
           HeadlessSurface.publish_source_update(
             memory_tracker_publication_attrs(:comment_create),
             matrix_opts
           ),
         {:ok, state_update} <-
           HeadlessSurface.publish_source_update(
             memory_tracker_publication_attrs(:state_update),
             matrix_opts
           ) do
      operations = [
        memory_tracker_operation("fetch_candidate_issues", candidates, %{
          "operation" => "linear.issues.list",
          "subject_count" => source_subject_count(candidates)
        }),
        memory_tracker_operation("fetch_issues_by_states", state_candidates, %{
          "operation" => "linear.issues.list",
          "state_names" => ["Todo"],
          "subject_count" => source_subject_count(state_candidates)
        }),
        memory_tracker_operation("fetch_issue_states_by_ids", current_states, %{
          "operation" => "linear.issues.list",
          "issue_ids" => value(current_states, :requested_issue_ids) || ["lin-issue-321"],
          "current_state_count" => current_state_count(current_states)
        }),
        memory_tracker_operation("create_comment", source_receipt(comment_create), %{
          "operation" => "linear.comments.create",
          "capability_id" => "linear.comments.create"
        }),
        memory_tracker_operation("update_issue_state", source_receipt(state_update), %{
          "operation" => "linear.issues.update",
          "capability_id" => "linear.issues.update",
          "state_name" => "Done"
        })
      ]

      %{
        "proof_source" => "fixture_memory_tracker",
        "fixture_backend" => inspect(HeadlessFixtureBackend),
        "appkit_surfaces" => ["AppKit.SourceSurface"],
        "live_provider_effect?" => false,
        "all_operations_covered?" =>
          Enum.map(operations, &Map.fetch!(&1, "symphony_callback")) == @memory_tracker_callbacks,
        "operations" => operations
      }
    else
      {:error, reason} ->
        %{
          "proof_source" => "fixture_memory_tracker",
          "fixture_backend" => inspect(HeadlessFixtureBackend),
          "appkit_surfaces" => ["AppKit.SourceSurface"],
          "live_provider_effect?" => false,
          "all_operations_covered?" => false,
          "error" => reason |> redact_secret_fields() |> inspect(),
          "operations" => []
        }
    end
  end

  defp memory_tracker_operation(callback, result, extra) do
    %{
      "symphony_module" => "SymphonyElixir.Tracker.Memory",
      "symphony_callback" => callback,
      "appkit_surface" => "AppKit.SourceSurface",
      "status" => "fixture_receipt_recorded",
      "source_binding_id" => value(result, :source_binding_id) || "linear-primary",
      "lower_request_ref" => value(result, :lower_request_ref),
      "lower_receipt_ref" => value(result, :lower_receipt_ref)
    }
    |> Map.merge(extra)
    |> compact_map()
  end

  defp source_receipt(result), do: value(result, :source_publication_receipt) || result

  defp memory_tracker_source_binding(state_names \\ nil) do
    filters =
      %{}
      |> maybe_put(:state_names, state_names)

    %{
      source_binding_id: "linear-primary",
      provider: "linear",
      connection_ref: "linear-primary",
      candidate_filters: filters,
      state_mapping: %{}
    }
  end

  defp memory_tracker_publication_attrs(:comment_create) do
    %{
      source_publish_ref: "linear_memory_tracker_comment_create",
      source_binding_id: "linear-primary",
      source_ref: "linear://fixture/issue/ENG-321",
      issue_id: "lin-issue-321",
      body: "Extravaganza deterministic memory tracker comment proof"
    }
  end

  defp memory_tracker_publication_attrs(:state_update) do
    %{
      source_publish_ref: "linear_memory_tracker_state_update",
      source_binding_id: "linear-primary",
      source_ref: "linear://fixture/issue/ENG-321",
      issue_id: "lin-issue-321",
      state_name: "Done",
      publication_kind: :issue_state_update
    }
  end

  defp memory_tracker_fixture_opts(opts) do
    opts
    |> Map.take([:tenant_id, :pack_version, :trace_id])
    |> Enum.to_list()
    |> Keyword.put(:source_backend, HeadlessFixtureBackend)
    |> Keyword.put(:skip_bootstrap?, true)
  end

  defp codex_turn_effect(example, _proof, opts) do
    config = Config.load(config_overrides(opts))
    context = AppKitContext.bootstrap_context(config)
    request = codex_agent_run_request(config, opts)
    surface_opts = surface_opts(opts)

    with {:ok, %RunOutcomeFuture{} = future} <-
           HeadlessSurface.invoke_coding_agent_runtime(request, surface_opts),
         {:ok, %RuntimeRunDetail{} = run_detail} <-
           AppKitHeadlessSurface.run_detail(
             context,
             future.run_ref,
             codex_readback_request(request),
             surface_opts
           ) do
      turn = codex_turn_readback(run_detail)
      first_prompt = codex_first_prompt_readback(run_detail, turn)
      continuation = codex_continuation_readback(run_detail)
      session_start = codex_session_start_readback(run_detail, turn)
      session_stop = codex_session_stop_readback(run_detail)
      app_server_protocol = codex_app_server_protocol_readback(run_detail, turn)
      event_stream = codex_event_stream_readback(run_detail)
      token_usage = value(event_stream, :token_usage) || %{}
      token_totals = codex_token_totals_readback(run_detail)
      timeout_policy = request |> value(:params) |> value(:timeout_policy) || %{}
      stall = codex_stall_readback(run_detail)
      last_message = value(event_stream, :last_message) || %{}
      lower_receipt_ref = value(turn, :lower_receipt_ref)
      provider_response_received? = truthy?(value(turn, :provider_response_received?))

      %{
        "provider" => example.provider,
        "effect" => example.provider_effect,
        "capability_ids" => example.capability_ids,
        "status" => "receipt_recorded",
        "operation" => value(turn, :operation) || "codex.session.turn",
        "credential_present?" => true,
        "credential_redeemed?" => truthy?(value(turn, :credential_redeemed?)),
        "provider_request_sent?" => truthy?(value(turn, :provider_request_sent?)),
        "provider_response_received?" => provider_response_received?,
        "receipt_recorded?" => present?(lower_receipt_ref),
        "product_readback_confirmed?" => runtime_readback_confirmed?(run_detail),
        "appkit_surfaces" => ["AppKit.RuntimeGateway", "AppKit.HeadlessSurface"],
        "run_ref" => future.run_ref,
        "workflow_ref" => future.workflow_ref,
        "session_ref" => value(turn, :session_ref) || runtime_session_ref(run_detail),
        "first_prompt_confirmed?" => codex_first_prompt_confirmed?(first_prompt),
        "prompt_ref" => value(first_prompt, :prompt_ref),
        "prompt_hash" => value(first_prompt, :prompt_hash),
        "prompt_hash_verified?" => truthy?(value(first_prompt, :prompt_hash_verified?)),
        "prompt_source_ref" => value(first_prompt, :prompt_source_ref),
        "prompt_rendered?" => truthy?(value(first_prompt, :prompt_rendered?)),
        "prompt_body_redacted?" => truthy?(value(first_prompt, :prompt_body_redacted?)),
        "prompt_body_included?" => truthy?(value(first_prompt, :prompt_body_included?)),
        "turn_count" => value(continuation, :turn_count),
        "max_turns" => value(continuation, :max_turns),
        "continuation_turn_count" => value(continuation, :continuation_turn_count),
        "continuation_turns_confirmed?" => codex_continuation_confirmed?(continuation),
        "continuation_guidance_ref" => value(continuation, :continuation_guidance_ref),
        "continuation_guidance_hash" => value(continuation, :continuation_guidance_hash),
        "continuation_guidance_source_ref" =>
          value(continuation, :continuation_guidance_source_ref),
        "continuation_guidance_rendered?" =>
          truthy?(value(continuation, :continuation_guidance_rendered?)),
        "continuation_prompt_body_redacted?" =>
          truthy?(value(continuation, :continuation_prompt_body_redacted?)),
        "continuation_prompt_body_included?" =>
          truthy?(value(continuation, :continuation_prompt_body_included?)),
        "first_prompt_reused_on_continuation?" =>
          truthy?(value(continuation, :first_prompt_reused_on_continuation?)),
        "max_turns_reached?" => truthy?(value(continuation, :max_turns_reached?)),
        "session_start_confirmed?" => codex_session_start_confirmed?(session_start),
        "runtime_control_session_ref" => value(session_start, :runtime_control_session_ref),
        "session_start_event_kind" => value(session_start, :session_start_event_kind),
        "session_start_lower_request_ref" =>
          value(session_start, :session_start_lower_request_ref),
        "session_start_lower_receipt_ref" =>
          value(session_start, :session_start_lower_receipt_ref),
        "session_stop_confirmed?" => codex_session_stop_confirmed?(session_stop),
        "session_stop_status" => value(session_stop, :session_stop_status),
        "session_stop_lower_request_ref" => value(session_stop, :session_stop_lower_request_ref),
        "session_stop_lower_receipt_ref" => value(session_stop, :session_stop_lower_receipt_ref),
        "app_server_protocol_confirmed?" =>
          codex_app_server_protocol_confirmed?(app_server_protocol),
        "app_server_transport" => value(app_server_protocol, :app_server_transport),
        "app_server_jsonrpc_methods" => value(app_server_protocol, :app_server_jsonrpc_methods),
        "app_server_initialization_confirmed?" =>
          truthy?(value(app_server_protocol, :app_server_initialization_confirmed?)),
        "app_server_thread_start_confirmed?" =>
          truthy?(value(app_server_protocol, :app_server_thread_start_confirmed?)),
        "app_server_turn_start_confirmed?" =>
          truthy?(value(app_server_protocol, :app_server_turn_start_confirmed?)),
        "app_server_cwd_validation_confirmed?" =>
          truthy?(value(app_server_protocol, :app_server_cwd_validation_confirmed?)),
        "app_server_lower_request_ref" =>
          value(app_server_protocol, :app_server_lower_request_ref),
        "app_server_lower_receipt_ref" =>
          value(app_server_protocol, :app_server_lower_receipt_ref),
        "provider_session_id" => value(app_server_protocol, :provider_session_id),
        "provider_turn_id" => value(app_server_protocol, :provider_turn_id),
        "event_stream_confirmed?" => codex_event_stream_confirmed?(event_stream),
        "event_count" => value(event_stream, :event_count),
        "event_terminal_status" => value(event_stream, :terminal_status),
        "completed_event_count" => value(event_stream, :completed_event_count),
        "failed_event_count" => value(event_stream, :failed_event_count),
        "cancelled_event_count" => value(event_stream, :cancelled_event_count),
        "malformed_event_count" => value(event_stream, :malformed_event_count),
        "timeout_event_count" => value(event_stream, :timeout_event_count),
        "approval_event_count" => value(event_stream, :approval_event_count),
        "approval_required_count" => value(event_stream, :approval_required_count),
        "approval_auto_approved_count" => value(event_stream, :approval_auto_approved_count),
        "user_input_event_count" => value(event_stream, :user_input_event_count),
        "user_input_required_count" => value(event_stream, :user_input_required_count),
        "user_input_auto_answered_count" => value(event_stream, :user_input_auto_answered_count),
        "token_usage_input_tokens" => value(token_usage, :input_tokens),
        "token_usage_output_tokens" => value(token_usage, :output_tokens),
        "token_usage_total_tokens" => value(token_usage, :total_tokens),
        "token_usage_source" => value(token_usage, :source),
        "token_accounting_confirmed?" => codex_token_accounting_confirmed?(token_totals),
        "token_totals_input_tokens" => value(token_totals, :total_input_tokens),
        "token_totals_output_tokens" => value(token_totals, :total_output_tokens),
        "token_totals_total_tokens" => value(token_totals, :total_tokens),
        "token_totals_cached_input_tokens" => value(token_totals, :cached_input_tokens),
        "token_totals_source" => value(token_totals, :source),
        "runtime_state" => value(run_detail.runtime_row, :state),
        "runtime_status_reason" => value(run_detail.runtime_row, :status_reason),
        "configured_stall_timeout_ms" => value(timeout_policy, :stall_timeout_ms),
        "stall_decision_present?" => codex_stall_decision_present?(stall),
        "stall_elapsed_ms" => value(stall, :elapsed_ms),
        "stall_timeout_ms" => value(stall, :stall_timeout_ms),
        "stall_activity_source" => value(stall, :activity_source),
        "stall_safe_action" => value(stall, :safe_action),
        "stall_workflow_signal" => value(stall, :workflow_signal),
        "stall_cancel_lower_run?" => value(stall, :cancel_lower_run?),
        "rate_limits_present?" => truthy?(value(event_stream, :rate_limits_present?)),
        "rate_limit_id" => value(event_stream, :rate_limit_id),
        "rate_limit_primary_remaining" => value(event_stream, :rate_limit_primary_remaining),
        "rate_limit_primary_limit" => value(event_stream, :rate_limit_primary_limit),
        "last_codex_message_event_kind" => value(last_message, :event_kind),
        "last_codex_message_summary" => value(last_message, :summary),
        "last_codex_message_body_included?" => truthy?(value(last_message, :body_included?)),
        "turn_ref" => value(turn, :turn_ref),
        "lower_request_ref" => value(turn, :lower_request_ref),
        "lower_receipt_ref" => lower_receipt_ref
      }
      |> Map.merge(authority_effect_fields(turn))
      |> compact_map()
    else
      {:error, reason} ->
        failed_effect(example, reason)
    end
  end

  defp github_evidence_effect(example, _proof, opts) do
    case HeadlessSurface.collect_proposed_change_evidence(
           github_evidence_request(opts),
           surface_opts(opts)
         ) do
      {:ok, %GitHubPrEvidenceReceipt{} = receipt} ->
        %{
          "provider" => example.provider,
          "effect" => example.provider_effect,
          "capability_ids" => receipt.capability_ids,
          "status" => "receipt_recorded",
          "operation" => "github.pr.evidence",
          "repo" => receipt.repo,
          "pull_number" => receipt.pull_number,
          "head_sha" => receipt.head_sha,
          "evidence_ref" => receipt.evidence_ref,
          "credential_present?" => receipt.credential_present?,
          "credential_redeemed?" => receipt.credential_redeemed?,
          "provider_request_sent?" => receipt.provider_request_sent?,
          "provider_response_received?" => receipt.provider_response_received?,
          "receipt_recorded?" => receipt.receipt_recorded?,
          "product_readback_confirmed?" => receipt.product_readback_confirmed?,
          "fixture_setup_required?" => receipt.fixture_setup_required?,
          "write_operations" => receipt.write_operations,
          "provider_ids" => receipt.provider_ids,
          "provider_refs" => receipt.provider_refs,
          "counts" => receipt.counts,
          "receipt_refs" => receipt.receipt_refs,
          "operation_receipts" => receipt.operation_receipts,
          "appkit_surfaces" => ["AppKit.RuntimeGateway", "AppKit.HeadlessSurface"],
          "lower_request_ref" => first_ref(receipt.receipt_refs, "lower_request_refs"),
          "lower_receipt_ref" => first_ref(receipt.receipt_refs, "lower_receipt_refs")
        }
        |> Map.merge(authority_effect_fields(receipt))
        |> compact_map()
        |> Map.put("write_operations", receipt.write_operations || [])

      {:error, reason} ->
        failed_effect(example, reason)
    end
  end

  defp github_pr_cleanup_effect(example, _proof, opts) do
    case HeadlessSurface.cleanup_proposed_change_branch(
           github_pr_cleanup_request(opts),
           surface_opts(opts)
         ) do
      {:ok, %GitHubPrBranchCleanupReceipt{} = receipt} ->
        %{
          "provider" => example.provider,
          "effect" => example.provider_effect,
          "resource_effect_role_ref" => "proposed_change_cleanup",
          "capability_ids" => receipt.capability_ids,
          "status" => Atom.to_string(receipt.status),
          "operation" => "github.pr.branch_cleanup",
          "repo" => receipt.repo,
          "branch" => receipt.branch,
          "pull_numbers" => receipt.pull_numbers,
          "closed_pull_numbers" => receipt.closed_pull_numbers,
          "credential_present?" => receipt.credential_present?,
          "credential_redeemed?" => receipt.credential_redeemed?,
          "provider_request_sent?" => receipt.provider_request_sent?,
          "provider_response_received?" => receipt.provider_response_received?,
          "receipt_recorded?" => receipt.receipt_recorded?,
          "product_readback_confirmed?" => receipt.product_readback_confirmed?,
          "write_operations" => receipt.write_operations,
          "provider_ids" => receipt.provider_ids,
          "provider_refs" => receipt.provider_refs,
          "counts" => receipt.counts,
          "receipt_refs" => receipt.receipt_refs,
          "operation_receipts" => receipt.operation_receipts,
          "appkit_surfaces" => ["AppKit.RuntimeGateway", "AppKit.HeadlessSurface"],
          "lower_request_ref" => first_ref(receipt.receipt_refs, "lower_request_refs"),
          "lower_receipt_ref" => first_ref(receipt.receipt_refs, "lower_receipt_refs")
        }
        |> Map.merge(authority_effect_fields(receipt))
        |> compact_map()

      {:error, reason} ->
        failed_effect(example, reason)
    end
  end

  defp failed_effect(example, reason) do
    %{
      "provider" => example.provider,
      "effect" => example.provider_effect,
      "capability_ids" => example.capability_ids,
      "status" => "failed",
      "credential_present?" => true,
      "credential_redeemed?" => false,
      "provider_request_sent?" => false,
      "provider_response_received?" => false,
      "receipt_recorded?" => false,
      "product_readback_confirmed?" => false,
      "error" => reason |> redact_secret_fields() |> inspect()
    }
  end

  defp example_status(%{"status" => "receipt_recorded"}), do: "completed"
  defp example_status(%{"status" => "governed_denial_recorded"}), do: "completed"
  defp example_status(%{"status" => "failed"}), do: "failed"
  defp example_status(_provider_effect), do: "skipped"

  defp source_publication_effect_status(receipt) do
    if source_publication_denial?(receipt),
      do: "governed_denial_recorded",
      else: "receipt_recorded"
  end

  defp source_publication_denial?(receipt) do
    value(receipt, :status) in ["dry_run_denied", "denied"] or
      present?(value(receipt, :lower_denial_ref))
  end

  defp source_publication_ref(_receipt, true), do: nil

  defp source_publication_ref(receipt, false) do
    value(receipt, :source_publication_receipt_ref) || value(receipt, :source_publication_ref)
  end

  defp linear_source_binding(opts) do
    config = Config.load(config_overrides(opts))

    filters =
      %{}
      |> maybe_put(:assignee, linear_source_assignee_filter(opts))
      |> maybe_put(:state_names, source_state_names(opts))
      |> maybe_put(:project_slug, string_value(opts, :project_slug))
      |> maybe_put(:team_id, string_value(opts, :team_id))

    ProductPack.source_binding_snapshot(config, %{
      source_binding_id: "linear-primary",
      connection_ref: "linear-primary",
      candidate_filters: filters
    })
  end

  defp linear_publication_source_binding(opts) do
    opts
    |> config_overrides()
    |> ProductPack.source_binding_snapshot(%{
      source_binding_id: "linear-primary",
      connection_ref: "linear-primary",
      candidate_filters: %{}
    })
  end

  defp linear_source_assignee_filter(opts) do
    case linear_source_assignee_label(opts) do
      "all" -> nil
      assignee -> assignee
    end
  end

  defp linear_source_assignee_label(opts), do: string_value(opts, :assignee) || "me"

  defp linear_publication_attrs(opts) do
    case string_value(opts, :issue_id) do
      issue_id when is_binary(issue_id) ->
        {:ok, linear_publication_attrs!(opts, issue_id)}

      nil ->
        with {:ok, issue} <- resolve_live_publication_issue(opts),
             {:ok, issue_id} <- publication_issue_id(issue) do
          {:ok,
           linear_publication_attrs!(opts, issue_id, publication_source_ref(issue, issue_id))}
        end
    end
  end

  defp linear_publication_attrs!(opts, issue_id, source_ref \\ nil) do
    source_binding = linear_publication_source_binding(opts)

    %{
      source_publish_ref: "linear_live_publication",
      source_binding: source_binding,
      source_binding_id: Map.fetch!(source_binding, :source_binding_id),
      source_ref: source_ref || "linear://primary/issue/#{issue_id}",
      issue_id: issue_id,
      body: string_value(opts, :message) || "Extravaganza headless live publication proof",
      allow_create_fallback?: allow_create_fallback?(opts)
    }
    |> maybe_put(:comment_id, string_value(opts, :comment_id))
    |> maybe_put(:state_id, string_value(opts, :state_id))
    |> maybe_put(:state_name, string_value(opts, :state_name))
    |> maybe_put(:team_id, string_value(opts, :team_id))
    |> maybe_put(:publication_kind, linear_publication_kind(opts))
  end

  defp allow_create_fallback?(opts) do
    case Map.fetch(opts, :allow_create_fallback?) do
      {:ok, value} -> truthy?(value)
      :error -> true
    end
  end

  defp linear_publication_kind(opts) do
    if string_value(opts, :state_id) || string_value(opts, :state_name),
      do: :issue_state_update,
      else: nil
  end

  defp resolve_live_publication_issue(opts) do
    source_opts = surface_opts(opts) |> Keyword.put_new(:first, 1)

    case HeadlessSurface.fetch_source_candidates(
           linear_publication_source_binding(opts),
           source_opts
         ) do
      {:ok, result} -> result |> publication_candidates() |> first_publication_issue()
      {:error, reason} -> {:error, reason}
    end
  end

  defp publication_candidates(result) do
    source_intake = value(result, :source_intake)

    (source_intake |> value(:subject_attrs) |> List.wrap()) ++
      (source_intake |> value(:issues) |> List.wrap())
  end

  defp first_publication_issue(candidates) do
    candidates
    |> Enum.find(&publication_issue?/1)
    |> case do
      %{} = issue -> {:ok, issue}
      _missing -> {:error, :missing_live_linear_publication_issue}
    end
  end

  defp publication_issue?(%{} = issue) do
    is_binary(string_value(issue, :provider_external_ref) || string_value(issue, :id))
  end

  defp publication_issue?(_issue), do: false

  defp publication_issue_id(issue) do
    case string_value(issue, :provider_external_ref) || string_value(issue, :id) do
      issue_id when is_binary(issue_id) -> {:ok, issue_id}
      _missing -> {:error, :missing_live_linear_publication_issue}
    end
  end

  defp publication_source_ref(issue, issue_id) do
    string_value(issue, :source_ref) ||
      case string_value(issue, :identifier) do
        identifier when is_binary(identifier) -> "linear://primary/issue/#{identifier}"
        _missing -> "linear://primary/issue/#{issue_id}"
      end
  end

  defp source_intake_operation(result) do
    result
    |> value(:source_intake)
    |> value(:operation)
  end

  defp source_subject_count(result) do
    result
    |> value(:source_intake)
    |> value(:subject_attrs)
    |> List.wrap()
    |> length()
  end

  defp source_subjects(result) do
    result
    |> value(:source_intake)
    |> value(:subject_attrs)
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.map(&redact_secret_fields/1)
  end

  defp current_state_count(result) do
    current_state = value(result, :source_current_state)

    cond do
      is_list(value(current_state, :subject_attrs)) ->
        current_state |> value(:subject_attrs) |> length()

      is_map(value(result, :states)) ->
        result |> value(:states) |> map_size()

      true ->
        0
    end
  end

  defp current_state_issue_ids(opts) do
    issue_ids =
      opts
      |> value(:issue_ids)
      |> List.wrap()
      |> Enum.flat_map(&split_csv/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    cond do
      issue_ids != [] ->
        {:ok, issue_ids}

      is_binary(string_value(opts, :issue_id)) ->
        {:ok, [string_value(opts, :issue_id)]}

      true ->
        with {:ok, issue} <- resolve_live_publication_issue(opts),
             {:ok, issue_id} <- publication_issue_id(issue) do
          {:ok, [issue_id]}
        end
    end
  end

  defp source_state_names(opts) do
    opts
    |> value(:source_state_names)
    |> List.wrap()
    |> Enum.flat_map(&split_csv/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      names -> Enum.uniq(names)
    end
  end

  defp viewer_operation(result) do
    if present?(value(result, :viewer_resolution)), do: "linear.users.get_self"
  end

  defp product_readback_confirmed?(proof), do: Map.get(proof, "readback_count", 0) > 0

  defp runtime_readback_confirmed?(%RuntimeRunDetail{} = run_detail) do
    run_detail.runtime_row != nil and
      (Enum.any?(run_detail.events || []) or Enum.any?(run_detail.turns || []))
  end

  defp surface_opts(opts) do
    base =
      opts
      |> Map.take([
        :tenant_id,
        :pack_version,
        :trace_id,
        :api_key,
        :connection_id,
        :credential_ref,
        :credential_lease_ref,
        :dry_run?
      ])
      |> Enum.to_list()

    base
    |> put_keyword_new_present(:api_key, string_value(opts, :linear_api_key))
    |> put_keyword_new_present(:skip_bootstrap?, live_product_surface_proof?(opts))
    |> put_keyword_new_present(:first, positive_integer_value(opts, :limit))
    |> put_keyword_new_present(:cursor, string_value(opts, :cursor))
  end

  defp live_product_surface_proof?(%{live_product_path?: true}), do: true
  defp live_product_surface_proof?(_opts), do: nil

  defp config_overrides(opts) do
    opts
    |> Map.take([:tenant_id, :pack_version])
    |> Enum.to_list()
  end

  defp codex_agent_run_request(%Config{} = config, opts) do
    trace_id = string_value(opts, :trace_id) || "trace://extravaganza/live-codex-turn"
    dedupe_key = "extravaganza-live-codex-turn-#{ref_suffix(config.pack_version)}"
    initial_input = codex_initial_input(config, opts)
    continuation_input = codex_continuation_input(config, opts)

    %{
      tenant_ref: "tenant://#{config.tenant_id}",
      installation_ref: "installation://extravaganza/live-codex-turn",
      subject_ref: "subject://extravaganza/live-codex-turn",
      actor_ref: "actor://extravaganza/operator",
      profile_bundle: ProductPack.agent_loop_profile_slots(config),
      tool_catalog_ref: "tool-catalog://extravaganza/codex-live-v1",
      budget_ref: "budget://extravaganza/live-codex-turn",
      recall_scope_ref: "recall://extravaganza/live-codex-turn",
      idempotency_key: "live-codex-turn:#{ref_suffix(trace_id)}",
      trace_id: trace_id,
      correlation_id: "corr://extravaganza/live-codex-turn/#{ref_suffix(trace_id)}",
      submission_dedupe_key: dedupe_key,
      initial_input_ref: "prompt://extravaganza/live-codex-turn",
      params: %{
        capability_id: "codex.session.turn",
        provider_family: "codex",
        lower_runtime_kind: "codex_session",
        provider_effect?: true,
        max_turns: 2,
        initial_input: initial_input,
        continuation_policy: %{
          mode: "until_max_turns",
          active_state?: true
        },
        timeout_policy: codex_timeout_policy(config, opts),
        continuation_input: continuation_input,
        fixture_script: "success_first_try",
        release_manifest_ref: "release-manifest://extravaganza/live-codex-turn/v1"
      }
    }
  end

  defp codex_initial_input(%Config{} = config, _opts) do
    body = codex_first_turn_prompt(config)

    %{
      body: body,
      input_ref: "prompt://extravaganza/live-codex-turn",
      content_hash: prompt_hash(body),
      source_ref: "workflow://extravaganza/live-codex-turn/default",
      rendered?: true,
      body_redacted?: true,
      redaction_policy_ref: "redaction://prompt/excerpt-only",
      template_ref: "prompt-template://extravaganza/live-codex-turn/default"
    }
  end

  defp codex_continuation_input(%Config{} = _config, _opts) do
    body = codex_continuation_guidance()

    %{
      body: body,
      input_ref: "continuation-guidance://extravaganza/live-codex-turn/2",
      content_hash: prompt_hash(body),
      source_ref: "workflow://extravaganza/live-codex-turn/default",
      rendered?: true,
      body_redacted?: true,
      redaction_policy_ref: "redaction://prompt/excerpt-only",
      template_ref: "continuation-template://extravaganza/live-codex-turn/default"
    }
  end

  defp codex_timeout_policy(%Config{} = _config, _opts) do
    %{
      turn_timeout_ms: 3_600_000,
      stall_timeout_ms: 300_000
    }
  end

  defp codex_continuation_guidance do
    """
    Continuation guidance:

    - The previous Codex turn completed normally, but the live product proof subject is still active.
    - This is continuation turn #2 of 2 for the current agent run.
    - Resume from the current workspace and prior thread context instead of restarting from scratch.
    - Do not restate the original task instructions before acting.
    - Return one concise sentence confirming continuation handling and do not modify files.
    """
    |> String.trim()
  end

  defp codex_first_turn_prompt(%Config{} = config) do
    profile_slots = ProductPack.agent_loop_profile_slots(config)

    """
    #{CodingOpsTemplates.system_prompt()}

    ## Task

    Issue: {{ issue.identifier }} {{ issue.title }}
    State: {{ issue.state | default: "ready" }}
    Labels: {{ issue.labels | join: ", " }}
    Turn: {{ turn_number }} of {{ max_turns }}
    Runtime profile: {{ runtime_profile_ref }}
    Source binding: {{ source_binding_ref }}
    Redaction profile: {{ redaction_profile_ref }}

    {{ issue.description | default: "Confirm the live Codex product path is operational and return one concise sentence. Do not modify files." }}
    """
    |> CodingOpsTemplates.render_prompt_template(%{
      "issue" => %{
        "identifier" => "LIVE-CODEX-001",
        "title" => "Confirm the live Codex product path",
        "description" =>
          "Confirm the live Codex product path is operational and return one concise sentence. Do not modify files.",
        "state" => "ready",
        "labels" => ["live", "codex", "headless"]
      },
      "turn_number" => 1,
      "max_turns" => 1,
      "runtime_profile_ref" => profile_slots.runtime_profile_ref,
      "source_binding_ref" => ProductPack.source_binding_key(config),
      "redaction_profile_ref" => "redaction://prompt/excerpt-only",
      "authorized_tool_refs" => ["codex.session.turn"],
      "attempt" => 1
    })
    |> case do
      {:ok, prompt} ->
        String.trim(prompt)

      {:error, reason} ->
        raise ArgumentError, "invalid live Codex prompt template: #{inspect(reason)}"
    end
  end

  defp codex_readback_request(request) do
    %{
      subject_ref: request.subject_ref,
      workflow_ref: nil,
      capability_id: "codex.session.turn",
      provider_family: "codex"
    }
  end

  defp github_evidence_request(opts) do
    trace_id = string_value(opts, :trace_id) || "trace://extravaganza/live-github-evidence"
    suffix = ref_suffix(trace_id)

    %{
      tenant_id: string_value(opts, :tenant_id) || "extravaganza-live-#{suffix}",
      installation_id: "installation://extravaganza/live-github-evidence",
      subject_id: "subject://extravaganza/live-github-evidence",
      execution_id: "execution://extravaganza/live-github-evidence/#{suffix}",
      actor_id: "actor://extravaganza/operator",
      trace_id: trace_id,
      repo: string_value(opts, :repo) || "nshkrdotcom/extravaganza"
    }
    |> maybe_put(:pull_number, positive_integer_value(opts, :pull_number))
    |> maybe_put(:ref, string_value(opts, :ref))
  end

  defp github_pr_cleanup_request(opts) do
    trace_id = string_value(opts, :trace_id) || "trace://extravaganza/live-github-pr-cleanup"
    suffix = ref_suffix(trace_id)

    %{
      tenant_id: string_value(opts, :tenant_id) || "extravaganza-live-#{suffix}",
      installation_id: "installation://extravaganza/live-github-pr-cleanup",
      subject_id: "subject://extravaganza/live-github-pr-cleanup",
      execution_id: "execution://extravaganza/live-github-pr-cleanup/#{suffix}",
      actor_id: "actor://extravaganza/operator",
      trace_id: trace_id,
      repo: string_value(opts, :repo) || "nshkrdotcom/extravaganza",
      branch: string_value(opts, :branch) || "cleanup-branch",
      confirm_close?: truthy?(Map.get(opts, :confirm_close?))
    }
    |> maybe_put(:pull_number, positive_integer_value(opts, :pull_number))
    |> maybe_put(:closing_comment, string_value(opts, :closing_comment))
  end

  defp linear_graphql_tool_request(opts) do
    with {:ok, variables} <- linear_graphql_variables(opts) do
      {:ok,
       %{
         query: string_value(opts, :query) || "query Viewer { viewer { id } }",
         variables: variables
       }}
    end
  end

  defp linear_graphql_variables(opts) do
    case string_value(opts, :variables_json) do
      nil ->
        {:ok, %{}}

      variables_json ->
        case Jason.decode(variables_json) do
          {:ok, %{} = variables} ->
            {:ok, variables}

          {:ok, _other} ->
            {:error, :linear_graphql_variables_json_must_decode_to_object}

          {:error, reason} ->
            {:error, {:invalid_linear_graphql_variables_json, Exception.message(reason)}}
        end
    end
  end

  defp codex_turn_readback(%RuntimeRunDetail{} = run_detail) do
    Enum.find(run_detail.turns || [], fn turn ->
      value(turn, :operation) == "codex.session.turn" or present?(value(turn, :turn_ref))
    end) || %{}
  end

  defp codex_first_prompt_readback(%RuntimeRunDetail{} = run_detail, turn) do
    %{}
    |> Map.merge(codex_first_prompt_from_extension(run_detail))
    |> Map.merge(codex_first_prompt_from_event(run_detail))
    |> Map.merge(codex_first_prompt_from_turn(turn))
  end

  defp codex_first_prompt_from_turn(turn) do
    %{
      "confirmed?" => if(truthy?(value(turn, :first_prompt_confirmed?)), do: true),
      "prompt_ref" => value(turn, :prompt_ref),
      "prompt_hash" => value(turn, :prompt_hash),
      "prompt_hash_verified?" => value(turn, :prompt_hash_verified?),
      "prompt_source_ref" => value(turn, :prompt_source_ref),
      "prompt_rendered?" => value(turn, :prompt_rendered?),
      "prompt_body_redacted?" => value(turn, :prompt_body_redacted?),
      "prompt_body_included?" => value(turn, :prompt_body_included?)
    }
    |> compact_map()
  end

  defp codex_first_prompt_from_extension(%RuntimeRunDetail{runtime_row: runtime_row}) do
    runtime_row
    |> value(:extensions)
    |> value("codex_first_prompt")
    |> case do
      %{} = evidence ->
        %{
          "confirmed?" => if(truthy?(value(evidence, "confirmed?")), do: true),
          "prompt_ref" => value(evidence, :prompt_ref),
          "prompt_hash" => value(evidence, :prompt_hash),
          "prompt_hash_verified?" => value(evidence, :prompt_hash_verified?),
          "prompt_source_ref" => value(evidence, :prompt_source_ref),
          "prompt_rendered?" => value(evidence, :prompt_rendered?),
          "prompt_body_redacted?" => value(evidence, :prompt_body_redacted?),
          "prompt_body_included?" => value(evidence, :prompt_body_included?)
        }
        |> compact_map()

      _missing ->
        %{}
    end
  end

  defp codex_first_prompt_from_event(%RuntimeRunDetail{} = run_detail) do
    run_detail.events
    |> List.wrap()
    |> Enum.find(&(value(&1, :event_kind) == "codex.first_prompt.confirmed"))
    |> case do
      nil ->
        %{}

      event ->
        extensions = value(event, :extensions) || %{}

        %{
          "confirmed?" => true,
          "prompt_ref" => value(extensions, :prompt_ref),
          "prompt_hash" => value(extensions, :prompt_hash),
          "prompt_hash_verified?" => value(extensions, :prompt_hash_verified?),
          "prompt_source_ref" => value(extensions, :prompt_source_ref),
          "prompt_rendered?" => value(extensions, :prompt_rendered?),
          "prompt_body_redacted?" => value(extensions, :prompt_body_redacted?),
          "prompt_body_included?" => value(extensions, :prompt_body_included?)
        }
        |> compact_map()
    end
  end

  defp codex_first_prompt_confirmed?(evidence) do
    truthy?(value(evidence, "confirmed?")) or
      present?(value(evidence, :prompt_ref)) or
      present?(value(evidence, :prompt_hash))
  end

  defp codex_continuation_readback(%RuntimeRunDetail{} = run_detail) do
    %{}
    |> Map.merge(codex_continuation_from_extension(run_detail))
    |> Map.merge(codex_continuation_from_event(run_detail))
    |> Map.merge(codex_continuation_from_turns(run_detail))
  end

  defp codex_continuation_from_extension(%RuntimeRunDetail{runtime_row: runtime_row}) do
    runtime_row
    |> value(:extensions)
    |> value("codex_continuation")
    |> case do
      %{} = evidence -> evidence
      _missing -> %{}
    end
  end

  defp codex_continuation_from_event(%RuntimeRunDetail{} = run_detail) do
    run_detail.events
    |> List.wrap()
    |> Enum.find(&(value(&1, :event_kind) == "codex.continuation_turn.confirmed"))
    |> case do
      nil ->
        %{}

      event ->
        event
        |> value(:extensions)
        |> case do
          %{} = extensions -> Map.put(extensions, "confirmed?", true)
          _missing -> %{"confirmed?" => true}
        end
    end
  end

  defp codex_continuation_from_turns(%RuntimeRunDetail{} = run_detail) do
    turns = List.wrap(run_detail.turns)
    continuation_turns = Enum.filter(turns, &truthy?(value(&1, :continuation?)))

    %{
      "turn_count" => if(turns != [], do: length(turns)),
      "continuation_turn_count" => if(continuation_turns != [], do: length(continuation_turns)),
      "confirmed?" => if(continuation_turns != [], do: true)
    }
    |> compact_map()
  end

  defp codex_continuation_confirmed?(evidence) do
    truthy?(value(evidence, "confirmed?")) or
      truthy?(value(evidence, :confirmed?)) or
      (value(evidence, :continuation_turn_count) || 0) > 0
  end

  defp codex_session_start_readback(%RuntimeRunDetail{} = run_detail, turn) do
    %{}
    |> Map.merge(codex_session_start_from_extension(run_detail))
    |> Map.merge(codex_session_start_from_event(run_detail))
    |> Map.merge(codex_session_start_from_turn(turn))
  end

  defp codex_session_start_from_turn(turn) do
    %{
      "confirmed?" => if(truthy?(value(turn, :session_start_confirmed?)), do: true),
      "runtime_control_session_ref" => value(turn, :runtime_control_session_ref),
      "session_start_event_kind" => value(turn, :session_start_event_kind),
      "session_start_lower_request_ref" => value(turn, :session_start_lower_request_ref),
      "session_start_lower_receipt_ref" => value(turn, :session_start_lower_receipt_ref)
    }
    |> compact_map()
  end

  defp codex_session_start_from_extension(%RuntimeRunDetail{runtime_row: runtime_row}) do
    runtime_row
    |> value(:extensions)
    |> value("codex_app_server_session_start")
    |> case do
      %{} = evidence ->
        %{
          "confirmed?" => if(truthy?(value(evidence, "confirmed?")), do: true),
          "runtime_control_session_ref" => value(evidence, :runtime_control_session_ref),
          "session_start_event_kind" =>
            session_start_event_kind_from_lifecycle(value(evidence, :lifecycle)),
          "session_start_lower_request_ref" => value(evidence, :lower_request_ref),
          "session_start_lower_receipt_ref" => value(evidence, :lower_receipt_ref)
        }
        |> compact_map()

      _missing ->
        %{}
    end
  end

  defp codex_session_start_from_event(%RuntimeRunDetail{} = run_detail) do
    run_detail.events
    |> List.wrap()
    |> Enum.find(&(value(&1, :event_kind) in ["codex.session.started", "codex.session.reused"]))
    |> case do
      nil ->
        %{}

      event ->
        extensions = value(event, :extensions) || %{}

        %{
          "confirmed?" => true,
          "runtime_control_session_ref" => value(event, :session_ref),
          "session_start_event_kind" => value(event, :event_kind),
          "session_start_lower_request_ref" => value(extensions, :lower_request_ref),
          "session_start_lower_receipt_ref" => value(extensions, :lower_receipt_ref)
        }
        |> compact_map()
    end
  end

  defp codex_session_start_confirmed?(evidence) do
    truthy?(value(evidence, "confirmed?")) or
      truthy?(value(evidence, :session_start_confirmed?)) or
      present?(value(evidence, :runtime_control_session_ref))
  end

  defp session_start_event_kind_from_lifecycle("started"), do: "codex.session.started"
  defp session_start_event_kind_from_lifecycle(:started), do: "codex.session.started"
  defp session_start_event_kind_from_lifecycle("reused"), do: "codex.session.reused"
  defp session_start_event_kind_from_lifecycle(:reused), do: "codex.session.reused"
  defp session_start_event_kind_from_lifecycle(_lifecycle), do: nil

  defp codex_session_stop_readback(%RuntimeRunDetail{} = run_detail) do
    %{}
    |> Map.merge(codex_session_stop_from_extension(run_detail))
    |> Map.merge(codex_session_stop_from_event(run_detail))
  end

  defp codex_session_stop_from_extension(%RuntimeRunDetail{runtime_row: runtime_row}) do
    runtime_row
    |> value(:extensions)
    |> value("codex_app_server_session_stop")
    |> case do
      %{} = evidence ->
        %{
          "confirmed?" => if(truthy?(value(evidence, "confirmed?")), do: true),
          "runtime_control_session_ref" => value(evidence, :runtime_control_session_ref),
          "session_stop_status" => value(evidence, :status),
          "session_stop_lower_request_ref" => value(evidence, :lower_request_ref),
          "session_stop_lower_receipt_ref" => value(evidence, :lower_receipt_ref)
        }
        |> compact_map()

      _missing ->
        %{}
    end
  end

  defp codex_session_stop_from_event(%RuntimeRunDetail{} = run_detail) do
    run_detail.events
    |> List.wrap()
    |> Enum.find(&(value(&1, :event_kind) == "codex.session.stopped"))
    |> case do
      nil ->
        %{}

      event ->
        extensions = value(event, :extensions) || %{}

        %{
          "confirmed?" => true,
          "runtime_control_session_ref" => value(event, :session_ref),
          "session_stop_status" => value(extensions, :status),
          "session_stop_lower_request_ref" => value(extensions, :lower_request_ref),
          "session_stop_lower_receipt_ref" => value(extensions, :lower_receipt_ref)
        }
        |> compact_map()
    end
  end

  defp codex_session_stop_confirmed?(evidence) do
    truthy?(value(evidence, "confirmed?")) or
      present?(value(evidence, :session_stop_lower_receipt_ref)) or
      value(evidence, :session_stop_status) == "stopped"
  end

  defp codex_app_server_protocol_readback(%RuntimeRunDetail{} = run_detail, turn) do
    %{}
    |> Map.merge(codex_app_server_protocol_from_extension(run_detail))
    |> Map.merge(codex_app_server_protocol_from_event(run_detail))
    |> Map.merge(codex_app_server_protocol_from_turn(turn))
  end

  defp codex_app_server_protocol_from_turn(turn) do
    %{
      "confirmed?" => if(truthy?(value(turn, :app_server_protocol_confirmed?)), do: true),
      "app_server_transport" => value(turn, :app_server_transport),
      "app_server_jsonrpc_methods" => value(turn, :app_server_jsonrpc_methods),
      "app_server_initialization_confirmed?" =>
        value(turn, :app_server_initialization_confirmed?),
      "app_server_thread_start_confirmed?" => value(turn, :app_server_thread_start_confirmed?),
      "app_server_turn_start_confirmed?" => value(turn, :app_server_turn_start_confirmed?),
      "app_server_cwd_validation_confirmed?" =>
        value(turn, :app_server_cwd_validation_confirmed?),
      "app_server_lower_request_ref" => value(turn, :app_server_lower_request_ref),
      "app_server_lower_receipt_ref" => value(turn, :app_server_lower_receipt_ref),
      "provider_session_id" => value(turn, :provider_session_id),
      "provider_turn_id" => value(turn, :provider_turn_id)
    }
    |> compact_map()
  end

  defp codex_app_server_protocol_from_extension(%RuntimeRunDetail{runtime_row: runtime_row}) do
    runtime_row
    |> value(:extensions)
    |> value("codex_app_server_protocol")
    |> case do
      %{} = evidence ->
        %{
          "confirmed?" => if(truthy?(value(evidence, "confirmed?")), do: true),
          "app_server_transport" => value(evidence, :transport),
          "app_server_jsonrpc_methods" => value(evidence, :jsonrpc_methods),
          "app_server_initialization_confirmed?" => value(evidence, :initialization_confirmed?),
          "app_server_thread_start_confirmed?" => value(evidence, :thread_start_confirmed?),
          "app_server_turn_start_confirmed?" => value(evidence, :turn_start_confirmed?),
          "app_server_cwd_validation_confirmed?" => value(evidence, :cwd_validation_confirmed?),
          "app_server_lower_request_ref" => value(evidence, :lower_request_ref),
          "app_server_lower_receipt_ref" => value(evidence, :lower_receipt_ref),
          "provider_session_id" => value(evidence, :provider_session_id),
          "provider_turn_id" => value(evidence, :provider_turn_id)
        }
        |> compact_map()

      _missing ->
        %{}
    end
  end

  defp codex_app_server_protocol_from_event(%RuntimeRunDetail{} = run_detail) do
    run_detail.events
    |> List.wrap()
    |> Enum.find(&(value(&1, :event_kind) == "codex.app_server.protocol.confirmed"))
    |> case do
      nil ->
        %{}

      event ->
        extensions = value(event, :extensions) || %{}

        %{
          "confirmed?" => true,
          "app_server_transport" => value(extensions, :transport),
          "app_server_jsonrpc_methods" => value(extensions, :jsonrpc_methods),
          "app_server_cwd_validation_confirmed?" => value(extensions, :cwd_validation_confirmed?),
          "app_server_lower_request_ref" => value(extensions, :lower_request_ref),
          "app_server_lower_receipt_ref" => value(extensions, :lower_receipt_ref),
          "provider_session_id" => value(extensions, :provider_session_id),
          "provider_turn_id" => value(extensions, :provider_turn_id)
        }
        |> compact_map()
    end
  end

  defp codex_app_server_protocol_confirmed?(evidence) do
    truthy?(value(evidence, "confirmed?")) or
      truthy?(value(evidence, :app_server_initialization_confirmed?)) or
      present?(value(evidence, :app_server_transport))
  end

  defp codex_event_stream_readback(%RuntimeRunDetail{runtime_row: runtime_row}) do
    runtime_row
    |> value(:extensions)
    |> value("codex_event_stream")
    |> case do
      %{} = evidence -> evidence
      _missing -> %{}
    end
  end

  defp codex_event_stream_confirmed?(evidence) do
    truthy?(value(evidence, "confirmed?")) or
      truthy?(value(evidence, :confirmed?)) or
      positive_integer_value(evidence, :event_count) != nil
  end

  defp codex_token_totals_readback(%RuntimeRunDetail{runtime_row: runtime_row}) do
    case value(runtime_row, :token_totals) do
      %{} = totals -> totals
      _missing -> %{}
    end
  end

  defp codex_token_accounting_confirmed?(totals) do
    value(totals, :total_tokens) != nil or
      value(totals, :total_input_tokens) != nil or
      value(totals, :total_output_tokens) != nil or
      present?(value(totals, :source))
  end

  defp codex_stall_readback(%RuntimeRunDetail{runtime_row: runtime_row}) do
    runtime_row
    |> value(:extensions)
    |> value("stall")
    |> case do
      %{} = stall -> stall
      _missing -> %{}
    end
  end

  defp codex_stall_decision_present?(stall), do: map_size(stall) > 0

  defp runtime_session_ref(%RuntimeRunDetail{runtime_row: runtime_row}) do
    runtime_row
    |> value(:session_ref)
    |> value(:id)
  end

  defp redact_secret_fields(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> redact_secret_fields()
  end

  defp redact_secret_fields(%{} = map) do
    map
    |> Enum.map(fn {key, value} ->
      if secret_key?(key) do
        {key, "[REDACTED]"}
      else
        {key, redact_secret_fields(value)}
      end
    end)
    |> Map.new()
  end

  defp redact_secret_fields(list) when is_list(list), do: Enum.map(list, &redact_secret_fields/1)

  defp redact_secret_fields(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> redact_secret_fields() |> List.to_tuple()

  defp redact_secret_fields(value), do: value

  defp secret_key?(key)
       when key in [
              :api_key,
              :linear_api_key,
              :codex_api_key,
              :openai_api_key,
              :github_token,
              :gh_token,
              :access_token,
              :authorization,
              :secret,
              :token
            ],
       do: true

  defp secret_key?(key) when is_binary(key) do
    key
    |> String.downcase()
    |> then(
      &(&1 in [
          "api_key",
          "linear_api_key",
          "codex_api_key",
          "openai_api_key",
          "github_token",
          "gh_token",
          "access_token",
          "authorization",
          "secret",
          "token"
        ])
    )
  end

  defp secret_key?(_key), do: false

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp put_keyword_new_present(keyword, _key, nil), do: keyword
  defp put_keyword_new_present(keyword, _key, ""), do: keyword
  defp put_keyword_new_present(keyword, key, value), do: Keyword.put_new(keyword, key, value)

  defp split_csv(value) when is_binary(value), do: String.split(value, ",")
  defp split_csv(value), do: [to_string(value)]

  defp first_ref(receipt_refs, key) when is_map(receipt_refs) do
    receipt_refs
    |> value(key)
    |> List.wrap()
    |> Enum.find(&present?/1)
  end

  defp first_ref(_receipt_refs, _key), do: nil

  defp authority_effect_fields(values) when is_list(values) do
    Enum.reduce(values, %{}, fn value, acc -> Map.merge(acc, authority_effect_fields(value)) end)
  end

  defp authority_effect_fields(source) do
    source = authority_handoff_source(source)

    if authority_proof_present?(source) do
      %{
        "authority_authorized?" =>
          first_non_nil([
            boolean_value_or_nil(source, :authority_authorized?),
            boolean_value_or_nil(source, :authorized?)
          ]),
        "authority_handoff_ref" =>
          first_non_nil([value(source, :authority_handoff_ref), value(source, :handoff_ref)]),
        "authority_packet_ref" => value(source, :authority_packet_ref),
        "connector_binding_ref" => value(source, :connector_binding_ref),
        "credential_lease_ref" => value(source, :credential_lease_ref),
        "authority_raw_material_present?" =>
          first_non_nil([
            boolean_value_or_nil(source, :authority_raw_material_present?),
            boolean_value_or_nil(source, :raw_material_present?)
          ])
      }
      |> compact_map()
    else
      %{}
    end
  end

  defp authority_handoff_source(source) do
    metadata = value(source, :metadata)

    cond do
      authority_proof_present?(source) ->
        source

      is_map(value(source, :authority_handoff)) ->
        value(source, :authority_handoff)

      is_map(value(metadata, :authority_handoff)) ->
        value(metadata, :authority_handoff)

      true ->
        %{}
    end
  end

  defp authority_proof_present?(source) do
    Enum.any?(@authority_effect_keys, &(not is_nil(value(source, &1))))
  end

  defp boolean_value_or_nil(source, key) do
    case value(source, key) do
      value when is_boolean(value) -> value
      _other -> nil
    end
  end

  defp first_non_nil(values), do: Enum.find(values, &(not is_nil(&1)))

  defp value(%_{} = struct, key), do: struct |> Map.from_struct() |> value(key)

  defp value(%{} = map, key) when is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> nil
    end
  end

  defp value(%{} = map, key) when is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> atom_key_value(map, key)
    end
  end

  defp value(_value, _key), do: nil

  defp atom_key_value(map, key) do
    Enum.find_value(map, &matching_atom_key_value(&1, key))
  end

  defp matching_atom_key_value({atom_key, value}, key) when is_atom(atom_key) do
    if Atom.to_string(atom_key) == key, do: value
  end

  defp matching_atom_key_value(_entry, _key), do: nil

  defp string_value(map, key) do
    case value(map, key) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      _other -> nil
    end
  end

  defp positive_integer_value(map, key) do
    case value(map, key) do
      value when is_integer(value) and value > 0 ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer > 0 -> integer
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", [], %{}] end)
    |> Map.new()
  end

  defp product_proof(%{fixture: _fixture}), do: fixture_product_proof()
  defp product_proof(%{live_product_path?: true}), do: fixture_product_proof()

  defp product_proof(opts) do
    case Application.get_env(:extravaganza_core, :headless_fixture_context?) do
      true -> fixture_product_proof()
      _other -> same_run_product_proof(opts)
    end
  end

  defp same_run_product_proof(opts) do
    smoke_opts =
      opts
      |> Map.take([:tenant_id, :pack_version])
      |> Map.put(:deterministic?, true)
      |> Map.put(:same_run?, true)

    with {:ok, %{"proof" => proof}} <-
           ProductHost.same_run_smoke(smoke_opts) do
      {:ok,
       %{
         "proof_class" => Map.get(proof, "proof_class"),
         "proof_source" => "same_run_smoke",
         "subject_ref" => Map.fetch!(proof, "subject_ref"),
         "run_ref" => Map.fetch!(proof, "run_ref"),
         "workflow_ref" => Map.fetch!(proof, "workflow_ref"),
         "runtime_profile_ref" => Map.fetch!(proof, "runtime_profile_ref"),
         "authority_ref" => Map.fetch!(proof, "authority_ref"),
         "decision_ref" => Map.fetch!(proof, "decision_ref"),
         "connector_manifest_ref" => Map.fetch!(proof, "connector_manifest_ref"),
         "capability_negotiation_ref" => Map.fetch!(proof, "capability_negotiation_ref"),
         "lower_request_ref" => Map.fetch!(proof, "lower_request_ref"),
         "lower_receipt_ref" => Map.fetch!(proof, "lower_receipt_ref"),
         "source_publication_ref" => Map.fetch!(proof, "source_publication_ref"),
         "evidence_chain_ref" => Map.fetch!(proof, "evidence_chain_ref"),
         "event_page_ref" => Map.fetch!(proof, "event_page_ref"),
         "readback_count" => proof |> Map.get("readbacks", []) |> length()
       }}
    end
  end

  defp fixture_product_proof do
    opts = [backend: HeadlessFixtureBackend, skip_bootstrap?: true]

    with {:ok, _run} <- HeadlessSurface.run_detail("run:fixture", %{}, opts),
         {:ok, evidence} <- HeadlessSurface.evidence_chain("run:fixture", %{}, opts),
         {:ok, _events} <- HeadlessSurface.events(%{"run_id" => "run:fixture"}, opts),
         %{} <- Map.fetch!(evidence, "source_publication") do
      {:ok,
       %{
         "proof_class" => "product_fixture_headless",
         "proof_source" => "fixture_headless_surface",
         "subject_ref" => "subject:fixture",
         "run_ref" => "run:fixture",
         "workflow_ref" => "workflow:fixture",
         "runtime_profile_ref" => "runtime-profile:local-deterministic",
         "authority_ref" => "authority:fixture",
         "decision_ref" => "decision:fixture",
         "connector_manifest_ref" => "manifest:fixture",
         "capability_negotiation_ref" => "capability-negotiation:fixture",
         "lower_request_ref" => "lower-request:fixture",
         "lower_receipt_ref" => "lower-receipt:fixture",
         "source_publication_ref" => "source-publication:fixture",
         "evidence_chain_ref" => "evidence-chain:run:fixture",
         "event_page_ref" => "event-page:run:fixture",
         "readback_count" => 4
       }}
    end
  end

  defp product_path(proof, entrypoint, provider_effect \\ %{}) do
    %{
      "entrypoint" => entrypoint,
      "proof_source" => Map.fetch!(proof, "proof_source"),
      "appkit_surfaces" => appkit_surfaces(proof, provider_effect),
      "lower_path" => lower_path(proof),
      "lower_path_status" => lower_path_status(proof),
      "readback_count" => Map.get(proof, "readback_count")
    }
  end

  defp appkit_surfaces(_proof, %{"appkit_surfaces" => [_ | _] = surfaces}), do: surfaces

  defp appkit_surfaces(%{"proof_source" => "fixture_headless_surface"}, _provider_effect),
    do: ["AppKit.HeadlessSurface"]

  defp appkit_surfaces(_proof, _provider_effect),
    do: [
      "AppKit.WorkSurface",
      "AppKit.WorkControl",
      "AppKit.SourceSurface",
      "AppKit.HeadlessSurface"
    ]

  defp lower_path(%{"proof_source" => "fixture_headless_surface"}), do: []

  defp lower_path(_proof), do: ["AppKit", "Mezzanine", "Citadel", "GovernedIntegration"]

  defp lower_path_status(%{"proof_source" => "fixture_headless_surface"}),
    do: "skipped_before_live_provider_effect"

  defp lower_path_status(_proof), do: "deterministic_lower_receipt_recorded"

  defp common_refs(proof) do
    Map.take(proof, [
      "subject_ref",
      "run_ref",
      "workflow_ref",
      "runtime_profile_ref",
      "authority_ref",
      "decision_ref",
      "connector_manifest_ref",
      "capability_negotiation_ref",
      "lower_request_ref",
      "lower_receipt_ref",
      "source_publication_ref",
      "evidence_chain_ref",
      "event_page_ref"
    ])
  end

  defp provider_effect_refs(refs, provider_effect) do
    refs
    |> maybe_put_ref(
      "connector_manifest_ref",
      first_operation_ref(provider_effect, "connector_manifest_ref")
    )
    |> maybe_put_ref(
      "capability_negotiation_ref",
      first_operation_ref(provider_effect, "capability_negotiation_ref")
    )
    |> maybe_put_ref("lower_request_ref", Map.get(provider_effect, "lower_request_ref"))
    |> maybe_put_ref("lower_receipt_ref", Map.get(provider_effect, "lower_receipt_ref"))
    |> provider_source_publication_ref(provider_effect)
  end

  defp provider_source_publication_ref(refs, %{"source_publication_ref" => value})
       when is_binary(value) and value != "",
       do: Map.put(refs, "source_publication_ref", value)

  defp provider_source_publication_ref(refs, _provider_effect),
    do: Map.delete(refs, "source_publication_ref")

  defp first_operation_ref(%{"operation_receipts" => receipts}, key) when is_list(receipts) do
    Enum.find_value(receipts, &value(&1, key))
  end

  defp first_operation_ref(_provider_effect, _key), do: nil

  defp maybe_put_ref(refs, _key, nil), do: refs
  defp maybe_put_ref(refs, _key, ""), do: refs
  defp maybe_put_ref(refs, key, value), do: Map.put(refs, key, value)

  defp example_mode_fields(opts, proofish) do
    live_product_path? = live_product_path?(opts)

    %{
      "example_mode" =>
        if(live_product_path?, do: "live_product_path", else: "deterministic_fixture"),
      "deterministic_fixture?" => not live_product_path?,
      "fixture_backed?" => not live_product_path?,
      "live_product_path?" => live_product_path?,
      "live_provider_effect?" => live_product_path? and live_provider_effect_recorded?(proofish),
      "requires_live_product_path?" => true
    }
  end

  defp annotate_provider_effect(provider_effect, opts) do
    Map.merge(provider_effect, %{
      "deterministic_fixture?" => deterministic_fixture?(opts),
      "fixture_backed?" => deterministic_fixture?(opts),
      "live_product_path?" => live_product_path?(opts),
      "live_provider_effect?" =>
        live_product_path?(opts) and live_provider_effect_recorded?(provider_effect)
    })
  end

  defp live_provider_effect_recorded?(%{"all_provider_effects_completed?" => true}), do: true

  defp live_provider_effect_recorded?(%{"status" => status})
       when status in ["receipt_recorded", "governed_denial_recorded"],
       do: true

  defp live_provider_effect_recorded?(%{"provider_request_sent?" => true}), do: true
  defp live_provider_effect_recorded?(_value), do: false

  defp skip_reason(kind, example, opts) do
    cond do
      credential_ref_present?(opts) ->
        %{
          "code" => "credential_ref_requires_connection_id",
          "provider" => example.provider,
          "credential_refs" => example.credential_refs,
          "detail" =>
            "explicit credential refs are redacted metadata; provider dispatch requires the lower connection_id binding"
        }

      not live_product_path?(opts) and credential_supplied?(kind, opts) ->
        %{
          "code" => "live_product_path_required",
          "provider" => example.provider,
          "credential_refs" => example.credential_refs,
          "detail" =>
            "credential input was accepted only as redacted preflight metadata; live provider dispatch requires --live-product-path"
        }

      credential_supplied?(kind, opts) ->
        %{
          "code" => "live_provider_effect_deferred",
          "provider" => example.provider,
          "detail" =>
            "product command exercised the headless live example entrypoint; live provider effect remains gated to the owner lower bridge"
        }

      true ->
        %{
          "code" => "credential_not_supplied_to_product_command",
          "provider" => example.provider,
          "credential_refs" => example.credential_refs
        }
    end
  end

  defp credential_preflight(kind, example, opts) do
    connection_id = string_value(opts, :connection_id)
    credential_ref = string_value(opts, :credential_ref)
    credential_lease_ref = string_value(opts, :credential_lease_ref)
    stdin? = truthy?(Map.get(opts, :api_key_stdin?))
    available? = truthy?(Map.get(opts, :credential_available?))

    %{
      "provider" => example.provider,
      "status" => credential_preflight_status(kind, opts, connection_id, stdin?, available?),
      "dispatch_binding" => credential_dispatch_binding(kind, opts),
      "connection_id" => connection_id,
      "credential_ref" => credential_ref,
      "credential_lease_ref" => credential_lease_ref,
      "credential_source" => credential_source(kind, opts),
      "secret_material_present?" => stdin?,
      "secret_material_redacted?" => true
    }
    |> compact_map()
  end

  defp credential_preflight_status(kind, opts, connection_id, stdin?, available?) do
    cond do
      credential_ref_present?(opts) ->
        "missing_dispatch_binding"

      deterministic_credential_supplied?(kind, opts) ->
        "requires_live_product_path"

      deterministic_fixture?(opts) ->
        "fixture_only"

      dispatchable_credential?(kind, opts, connection_id, stdin?, available?) ->
        "dispatchable"

      true ->
        "missing"
    end
  end

  defp deterministic_credential_supplied?(kind, opts),
    do: deterministic_fixture?(opts) and credential_supplied?(kind, opts)

  defp dispatchable_credential?(kind, opts, connection_id, stdin?, available?) do
    present?(connection_id) or stdin? or available? or app_config_credential?(kind, opts)
  end

  defp app_config_credential?(kind, opts),
    do: kind in [:codex_turn, :github_evidence, :github_pr_cleanup] and live_product_path?(opts)

  defp credential_dispatch_binding(kind, opts) do
    cond do
      present?(string_value(opts, :connection_id)) ->
        "connection_id"

      truthy?(Map.get(opts, :api_key_stdin?)) ->
        "ephemeral_stdin"

      truthy?(Map.get(opts, :credential_available?)) ->
        "external_harness"

      kind in [:codex_turn, :github_evidence, :github_pr_cleanup] and
          truthy?(Map.get(opts, :live_product_path?)) ->
        "app_config"

      true ->
        nil
    end
  end

  defp credential_source(kind, opts) do
    cond do
      truthy?(Map.get(opts, :api_key_stdin?)) ->
        "stdin"

      present?(string_value(opts, :connection_id)) ->
        "connection_id"

      truthy?(Map.get(opts, :credential_available?)) ->
        "external_harness"

      kind in [:codex_turn, :github_evidence, :github_pr_cleanup] and
          truthy?(Map.get(opts, :live_product_path?)) ->
        "app_config"

      present?(string_value(opts, :credential_ref)) ->
        "credential_ref"

      present?(string_value(opts, :credential_lease_ref)) ->
        "credential_lease_ref"

      true ->
        nil
    end
  end

  defp credential_supplied?(kind, opts)
       when kind in [
              :linear_source,
              :linear_current_states,
              :linear_publication,
              :linear_graphql_tool
            ],
       do:
         truthy?(Map.get(opts, :api_key_stdin?)) or truthy?(Map.get(opts, :credential_available?)) or
           present?(string_value(opts, :connection_id))

  defp credential_supplied?(:codex_turn, opts),
    do:
      truthy?(Map.get(opts, :credential_available?)) or
        truthy?(Map.get(opts, :live_product_path?)) or
        present?(string_value(opts, :connection_id))

  defp credential_supplied?(:github_evidence, opts),
    do:
      truthy?(Map.get(opts, :credential_available?)) or
        truthy?(Map.get(opts, :live_product_path?)) or
        present?(string_value(opts, :connection_id))

  defp credential_supplied?(:github_pr_cleanup, opts),
    do:
      truthy?(Map.get(opts, :credential_available?)) or
        truthy?(Map.get(opts, :live_product_path?)) or
        present?(string_value(opts, :connection_id))

  defp credential_supplied?(_kind, opts),
    do:
      truthy?(Map.get(opts, :credential_available?)) or
        present?(string_value(opts, :connection_id))

  defp credential_ref_present?(opts) do
    not present?(string_value(opts, :connection_id)) and
      (present?(string_value(opts, :credential_ref)) or
         present?(string_value(opts, :credential_lease_ref)))
  end

  defp live_product_path?(opts), do: truthy?(Map.get(opts, :live_product_path?))
  defp deterministic_fixture?(opts), do: not live_product_path?(opts)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp prompt_hash(value) when is_binary(value) do
    digest = :crypto.hash(:sha256, value)
    "sha256:" <> Base.encode16(digest, case: :lower)
  end

  defp ref_suffix(ref) when is_binary(ref) do
    ref
    |> :binary.bin_to_list()
    |> Enum.reduce({[], false}, &ascii_alnum_dash_byte/2)
    |> elem(0)
    |> Enum.reverse()
    |> List.to_string()
    |> String.trim("-")
  end

  defp ref_suffix(ref), do: ref |> to_string() |> ref_suffix()

  defp ascii_alnum_dash_byte(byte, {chars, _previous_dash?}) when byte in ?A..?Z,
    do: {[byte | chars], false}

  defp ascii_alnum_dash_byte(byte, {chars, _previous_dash?}) when byte in ?a..?z,
    do: {[byte | chars], false}

  defp ascii_alnum_dash_byte(byte, {chars, _previous_dash?}) when byte in ?0..?9,
    do: {[byte | chars], false}

  defp ascii_alnum_dash_byte(_byte, {chars, true}), do: {chars, true}
  defp ascii_alnum_dash_byte(_byte, {chars, false}), do: {[?- | chars], true}

  defp aggregate_summary(examples) do
    required_operations = Enum.map(@example_order, &example!(&1).operation)
    completed_operations = operations_with_status(required_operations, examples, "completed")
    skipped_operations = operations_with_status(required_operations, examples, "skipped")
    failed_operations = operations_with_status(required_operations, examples, "failed")

    %{
      "required_operations" => required_operations,
      "completed_operations" => completed_operations,
      "skipped_operations" => skipped_operations,
      "failed_operations" => failed_operations,
      "provider_effect_count" => length(completed_operations),
      "all_provider_effects_completed?" => completed_operations == required_operations
    }
  end

  defp operations_with_status(required_operations, examples, status) do
    Enum.filter(required_operations, fn operation ->
      get_in(examples, [operation, "status"]) == status
    end)
  end

  defp aggregate_status(%{"failed_operations" => [_ | _]}), do: "failed"
  defp aggregate_status(%{"skipped_operations" => [_ | _]}), do: "skipped"
  defp aggregate_status(%{"all_provider_effects_completed?" => true}), do: "completed"
  defp aggregate_status(_summary), do: "failed"

  defp aggregate_source_publication_ref(examples) do
    examples
    |> value("live.linear-publication")
    |> case do
      %{} = publication ->
        value(publication, :source_publication_ref) ||
          publication |> value(:provider_effect) |> value(:source_publication_ref)

      _missing ->
        nil
    end
  end

  defp live_trace_id(opts, operation) do
    string_value(opts, :trace_id) ||
      "trace://extravaganza/#{operation |> String.replace(".", "-") |> String.replace("_", "-")}"
  end

  defp live_smoke_correlation_ref(trace_id), do: "live-smoke://#{ref_suffix(trace_id)}"

  defp live_receipt_ref(operation, proof) do
    run_ref = proof |> Map.fetch!("run_ref") |> URI.encode_www_form()
    operation_ref = operation |> String.replace(".", "/") |> String.replace("_", "-")
    "live-example-receipt://#{operation_ref}/#{run_ref}"
  end

  defp example!(kind), do: Map.fetch!(@provider_examples, kind)

  defp opts_map(opts) when is_map(opts), do: Map.new(opts)
  defp opts_map(opts) when is_list(opts), do: Map.new(opts)

  defp truthy?(value), do: value in [true, "true", 1, "1"]
end
