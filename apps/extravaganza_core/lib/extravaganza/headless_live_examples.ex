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
    proof
    |> common_refs()
    |> Map.merge(%{
      "status" => "skipped",
      "operation" => example.operation,
      "receipt_ref" => live_receipt_ref(example.operation, proof),
      "receipt_state" => "recorded",
      "provider" => example.provider,
      "capability_ids" => example.capability_ids,
      "credential_refs" => example.credential_refs,
      "command" => example.command,
      "product_path_exercised?" => true,
      "product_path" => product_path(proof, example.product_entrypoint),
      "provider_effect" => %{
        "provider" => example.provider,
        "effect" => example.provider_effect,
        "capability_ids" => example.capability_ids,
        "status" => "skipped",
        "skip_reason" => skip_reason(kind, example, opts)
      }
    })
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
