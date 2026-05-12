defmodule Extravaganza.HeadlessLiveExamples do
  @moduledoc false

  alias AppKit.Core.AgentIntake.RunOutcomeFuture
  alias AppKit.Core.RuntimeReadback.RuntimeRunDetail
  alias AppKit.Core.RuntimeSurface.GitHubPrEvidenceReceipt
  alias AppKit.HeadlessSurface, as: AppKitHeadlessSurface

  alias Extravaganza.{
    AppKitContext,
    Config,
    HeadlessSurface,
    ProductHost,
    ProductPack
  }

  @provider_examples %{
    linear_source: %{
      operation: "live.linear-source",
      provider: "linear",
      command: "mix extravaganza.headless.live.linear_source --json",
      product_entrypoint: "Extravaganza.ProductHost.live_linear_source_example",
      credential_refs: ["LINEAR_API_KEY"],
      capability_ids: ["linear.issues.list", "linear.issues.retrieve"],
      provider_effect: "source_intake"
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
    }
  }

  @example_order [:linear_source, :codex_turn, :linear_publication, :github_evidence]

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
          "examples" => examples
        })
        |> maybe_put("source_publication_ref", aggregate_source_publication_ref(examples))
        |> Map.merge(summary)

      {:ok, data}
    end
  end

  def run(kind, opts) when kind in @example_order do
    opts = opts_map(opts)
    example = example!(kind)

    with {:ok, proof} <- product_proof(opts) do
      {:ok, example_payload(kind, example, proof, opts)}
    end
  end

  defp example_payload(kind, example, proof, opts) do
    provider_effect = provider_effect(kind, example, proof, opts)

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
        "command" => example.command,
        "product_path_exercised?" => true,
        "product_path" => product_path(proof, example.product_entrypoint, provider_effect),
        "provider_effect" => provider_effect
      })

    payload
    |> maybe_put("source_publication_ref", Map.get(provider_effect, "source_publication_ref"))
    |> maybe_put("lower_request_ref", Map.get(provider_effect, "lower_request_ref"))
    |> maybe_put("lower_receipt_ref", Map.get(provider_effect, "lower_receipt_ref"))
  end

  defp provider_effect(kind, example, proof, opts) do
    cond do
      not credential_supplied?(kind, opts) ->
        %{
          "provider" => example.provider,
          "effect" => example.provider_effect,
          "capability_ids" => example.capability_ids,
          "status" => "skipped",
          "skip_reason" => skip_reason(kind, example, opts)
        }

      kind == :linear_source ->
        linear_source_effect(example, proof, opts)

      kind == :linear_publication ->
        linear_publication_effect(example, proof, opts)

      kind == :codex_turn ->
        codex_turn_effect(example, proof, opts)

      kind == :github_evidence ->
        github_evidence_effect(example, proof, opts)

      true ->
        %{
          "provider" => example.provider,
          "effect" => example.provider_effect,
          "capability_ids" => example.capability_ids,
          "status" => "skipped",
          "skip_reason" => skip_reason(kind, example, opts)
        }
    end
  end

  defp linear_source_effect(example, proof, opts) do
    case HeadlessSurface.fetch_linear_candidates(linear_source_binding(opts), surface_opts(opts)) do
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
          "lower_request_ref" => value(result, :lower_request_ref),
          "lower_receipt_ref" => value(result, :lower_receipt_ref)
        }
        |> compact_map()

      {:error, reason} ->
        failed_effect(example, reason)
    end
  end

  defp linear_publication_effect(example, proof, opts) do
    case linear_publication_attrs(opts) do
      {:ok, attrs} ->
        case HeadlessSurface.publish_linear_source(attrs, surface_opts(opts)) do
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
            |> compact_map()

          {:error, reason} ->
            failed_effect(example, reason)
        end

      {:error, reason} ->
        failed_effect(example, reason)
    end
  end

  defp codex_turn_effect(example, _proof, opts) do
    config = Config.load(config_overrides(opts))
    context = AppKitContext.bootstrap_context(config)
    request = codex_agent_run_request(config, opts)
    surface_opts = surface_opts(opts)

    with {:ok, %RunOutcomeFuture{} = future} <-
           AppKit.AgentIntake.start_agent_run(context, request, surface_opts),
         {:ok, %RuntimeRunDetail{} = run_detail} <-
           AppKitHeadlessSurface.run_detail(
             context,
             future.run_ref,
             codex_readback_request(request),
             surface_opts
           ) do
      turn = codex_turn_readback(run_detail)
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
        "appkit_surfaces" => ["AppKit.AgentIntake", "AppKit.HeadlessSurface"],
        "run_ref" => future.run_ref,
        "workflow_ref" => future.workflow_ref,
        "session_ref" => value(turn, :session_ref) || runtime_session_ref(run_detail),
        "turn_ref" => value(turn, :turn_ref),
        "lower_request_ref" => value(turn, :lower_request_ref),
        "lower_receipt_ref" => lower_receipt_ref
      }
      |> compact_map()
    else
      {:error, reason} ->
        failed_effect(example, reason)
    end
  end

  defp github_evidence_effect(example, _proof, opts) do
    case HeadlessSurface.fetch_github_pr_evidence(
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
          "appkit_surfaces" => ["AppKit.RuntimeSurface", "AppKit.HeadlessSurface"],
          "lower_request_ref" => first_ref(receipt.receipt_refs, "lower_request_refs"),
          "lower_receipt_ref" => first_ref(receipt.receipt_refs, "lower_receipt_refs")
        }
        |> compact_map()
        |> Map.put("write_operations", receipt.write_operations || [])

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

  defp linear_source_binding(_opts) do
    %{
      source_binding_id: "linear-primary",
      provider: "linear",
      connection_ref: "linear-primary",
      candidate_filters: %{assignee: "me"},
      state_mapping: %{
        "submitted" => ["Todo", "Backlog"],
        "retry_submission" => ["Todo"],
        "completed" => ["Done", "Completed"],
        "rejected" => ["Canceled", "Cancelled", "Duplicate"]
      }
    }
  end

  defp linear_publication_source_binding(_opts) do
    %{
      source_binding_id: "linear-primary",
      provider: "linear",
      connection_ref: "linear-primary",
      candidate_filters: %{},
      state_mapping: %{}
    }
  end

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
    %{
      source_publish_ref: "linear_live_publication",
      source_binding_id: "linear-primary",
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

    case HeadlessSurface.fetch_linear_candidates(
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

  defp product_readback_confirmed?(proof), do: Map.get(proof, "readback_count", 0) > 0

  defp runtime_readback_confirmed?(%RuntimeRunDetail{} = run_detail) do
    run_detail.runtime_row != nil and
      (Enum.any?(run_detail.events || []) or Enum.any?(run_detail.turns || []))
  end

  defp surface_opts(opts) do
    opts
    |> Map.take([:tenant_id, :pack_version, :trace_id, :linear_api_key, :dry_run?])
    |> Enum.to_list()
  end

  defp config_overrides(opts) do
    opts
    |> Map.take([:tenant_id, :pack_version])
    |> Enum.to_list()
  end

  defp codex_agent_run_request(%Config{} = config, opts) do
    trace_id = string_value(opts, :trace_id) || "trace://extravaganza/live-codex-turn"
    dedupe_key = "extravaganza-live-codex-turn-#{ref_suffix(config.pack_version)}"

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
        max_turns: 1,
        fixture_script: "success_first_try",
        release_manifest_ref: "release-manifest://extravaganza/live-codex-turn/v1"
      }
    }
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

  defp codex_turn_readback(%RuntimeRunDetail{} = run_detail) do
    Enum.find(run_detail.turns || [], fn turn ->
      value(turn, :operation) == "codex.session.turn" or present?(value(turn, :turn_ref))
    end) || %{}
  end

  defp runtime_session_ref(%RuntimeRunDetail{runtime_row: runtime_row}) do
    runtime_row
    |> value(:session_ref)
    |> value(:id)
  end

  defp runtime_session_ref(_run_detail), do: nil

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
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp first_ref(receipt_refs, key) when is_map(receipt_refs) do
    receipt_refs
    |> value(key)
    |> List.wrap()
    |> Enum.find(&present?/1)
  end

  defp first_ref(_receipt_refs, _key), do: nil

  defp value(%_{} = struct, key), do: struct |> Map.from_struct() |> value(key)

  defp value(%{} = map, key) when is_atom(key),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp value(%{} = map, key) when is_binary(key),
    do: Map.get(map, key) || Map.get(map, String.to_atom(key))

  defp value(_value, _key), do: nil

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
    with {:ok, _run} <- HeadlessSurface.run_detail("run:fixture", %{}, []),
         {:ok, _evidence} <- HeadlessSurface.evidence_chain("run:fixture", %{}, []),
         {:ok, _events} <- HeadlessSurface.events(%{"run_id" => "run:fixture"}, []),
         {:ok, _preview} <- HeadlessSurface.source_publication_preview("subject:fixture", []) do
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

  defp skip_reason(kind, example, opts) do
    if credential_supplied?(kind, opts) do
      %{
        "code" => "live_provider_effect_deferred",
        "provider" => example.provider,
        "detail" =>
          "product command exercised the headless live example entrypoint; live provider effect remains gated to the owner lower bridge"
      }
    else
      %{
        "code" => "credential_not_supplied_to_product_command",
        "provider" => example.provider,
        "credential_refs" => example.credential_refs
      }
    end
  end

  defp credential_supplied?(kind, opts) when kind in [:linear_source, :linear_publication],
    do: truthy?(Map.get(opts, :api_key_stdin?)) or truthy?(Map.get(opts, :credential_available?))

  defp credential_supplied?(:codex_turn, opts),
    do:
      truthy?(Map.get(opts, :credential_available?)) or
        truthy?(Map.get(opts, :live_product_path?))

  defp credential_supplied?(:github_evidence, opts),
    do:
      truthy?(Map.get(opts, :credential_available?)) or
        truthy?(Map.get(opts, :live_product_path?))

  defp credential_supplied?(_kind, opts), do: truthy?(Map.get(opts, :credential_available?))

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

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
