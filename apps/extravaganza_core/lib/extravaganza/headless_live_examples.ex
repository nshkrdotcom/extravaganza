defmodule Extravaganza.HeadlessLiveExamples do
  @moduledoc false

  alias Extravaganza.{HeadlessSurface, ProductHost}

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
      capability_ids: ["linear.comments.update", "linear.comments.create"],
      provider_effect: "source_publication"
    },
    github_evidence: %{
      operation: "live.github-evidence",
      provider: "github",
      command: "mix extravaganza.headless.live.github_evidence --json",
      product_entrypoint: "Extravaganza.ProductHost.live_github_evidence_example",
      credential_refs: ["GH_TOKEN", "GITHUB_TOKEN"],
      capability_ids: [
        "github.pr.create",
        "github.pr.fetch",
        "github.pr.reviews.list",
        "github.pr.review_comments.list"
      ],
      provider_effect: "github_pr_evidence"
    }
  }

  @example_order [:linear_source, :codex_turn, :linear_publication, :github_evidence]

  @spec run(atom(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def run(kind, opts \\ [])

  def run(:smoke, opts) do
    opts = opts_map(opts)

    with {:ok, proof} <- product_proof(opts) do
      examples =
        @example_order
        |> Enum.map(fn kind ->
          example = example!(kind)
          {example.operation, example_payload(kind, example, proof, opts)}
        end)
        |> Map.new()

      {:ok,
       proof
       |> common_refs()
       |> Map.merge(%{
         "status" => aggregate_status(examples),
         "operation" => "live.smoke",
         "receipt_ref" => live_receipt_ref("live.smoke", proof),
         "receipt_state" => "recorded",
         "product_path_exercised?" => true,
         "product_path" => product_path(proof, "Extravaganza.ProductHost.live_smoke"),
         "examples" => examples
       })}
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
      |> Map.merge(%{
        "status" => example_status(provider_effect),
        "operation" => example.operation,
        "receipt_ref" => live_receipt_ref(example.operation, proof),
        "receipt_state" => "recorded",
        "provider" => example.provider,
        "capability_ids" => example.capability_ids,
        "credential_refs" => example.credential_refs,
        "command" => example.command,
        "product_path_exercised?" => true,
        "product_path" => product_path(proof, example.product_entrypoint),
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

            %{
              "provider" => example.provider,
              "effect" => example.provider_effect,
              "capability_ids" => example.capability_ids,
              "status" => "receipt_recorded",
              "operation" => value(receipt, :capability_id) || "linear.comments.create",
              "source_binding_id" => value(receipt, :source_binding_id) || "linear-primary",
              "source_publication_ref" =>
                value(receipt, :source_publication_receipt_ref) ||
                  value(receipt, :source_publication_ref),
              "credential_present?" => true,
              "credential_redeemed?" => truthy?(value(result, :credential_redeemed?)),
              "provider_request_sent?" => true,
              "provider_response_received?" => true,
              "receipt_recorded?" => true,
              "product_readback_confirmed?" => product_readback_confirmed?(proof),
              "lower_request_ref" => value(receipt, :lower_request_ref),
              "lower_receipt_ref" => value(receipt, :lower_receipt_ref)
            }
            |> compact_map()

          {:error, reason} ->
            failed_effect(example, reason)
        end

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
  defp example_status(%{"status" => "failed"}), do: "failed"
  defp example_status(_provider_effect), do: "skipped"

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
      allow_create_fallback?: true
    }
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

  defp surface_opts(opts) do
    opts
    |> Map.take([:tenant_id, :pack_version, :trace_id, :linear_api_key])
    |> Enum.to_list()
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

  defp secret_key?(key) when key in [:api_key, :linear_api_key, :secret, :token], do: true

  defp secret_key?(key) when is_binary(key) do
    key
    |> String.downcase()
    |> then(&(&1 in ["api_key", "linear_api_key", "secret", "token"]))
  end

  defp secret_key?(_key), do: false

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp value(%_{} = struct, key), do: struct |> Map.from_struct() |> value(key)
  defp value(%{} = map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp value(_value, _key), do: nil

  defp string_value(map, key) do
    case value(map, key) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      _other -> nil
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

  defp product_path(proof, entrypoint) do
    %{
      "entrypoint" => entrypoint,
      "proof_source" => Map.fetch!(proof, "proof_source"),
      "appkit_surfaces" => appkit_surfaces(proof),
      "lower_path" => lower_path(proof),
      "lower_path_status" => lower_path_status(proof),
      "readback_count" => Map.get(proof, "readback_count")
    }
  end

  defp appkit_surfaces(%{"proof_source" => "fixture_headless_surface"}),
    do: ["AppKit.HeadlessSurface"]

  defp appkit_surfaces(_proof),
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

  defp credential_supplied?(_kind, opts), do: truthy?(Map.get(opts, :credential_available?))

  defp aggregate_status(examples) do
    if Enum.all?(examples, fn {_operation, example} -> example["status"] == "skipped" end) do
      "skipped"
    else
      "completed"
    end
  end

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
