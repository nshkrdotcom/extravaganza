defmodule Extravaganza.HeadlessLiveExamples do
  @moduledoc false

  alias Extravaganza.{HeadlessFixtureBackend, HeadlessSurface, ProductHost}
  alias Extravaganza.HeadlessLiveExamples.{Envelope, Lanes, Registry}

  @spec run(atom(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def run(kind, opts \\ [])

  def run(:smoke, opts) do
    opts = opts_map(opts)
    trace_id = Lanes.live_trace_id(opts, "live.smoke")

    with {:ok, proof} <- product_proof(opts) do
      examples =
        Registry.example_order()
        |> Enum.map(fn kind ->
          example = example!(kind)
          {example.operation, example_payload(kind, example, proof, opts)}
        end)
        |> Map.new()

      summary =
        examples
        |> Envelope.aggregate_summary(Enum.map(Registry.example_order(), &Registry.fetch!/1))

      data =
        Envelope.smoke_payload(
          proof,
          examples,
          summary,
          opts,
          trace_id,
          Lanes.deterministic_memory_tracker_matrix(opts)
        )

      {:ok, data}
    end
  end

  def run(kind, opts) do
    opts = opts_map(opts)

    if Registry.standalone_example?(kind) do
      example = example!(kind)

      with {:ok, proof} <- product_proof(opts) do
        {:ok, example_payload(kind, example, proof, opts)}
      end
    else
      {:error, {:unsupported_live_example, kind}}
    end
  end

  defp example_payload(kind, example, proof, opts) do
    provider_effect = Lanes.effect(kind, example, proof, opts)

    Envelope.example_payload(kind, example, proof, opts, provider_effect)
  end

  defp product_proof(%{fixture: _fixture}), do: fixture_product_proof()
  defp product_proof(%{live_product_path?: true}), do: fixture_product_proof()

  defp product_proof(opts) do
    if Lanes.value(opts, :headless_fixture_context?) == true,
      do: fixture_product_proof(),
      else: same_run_product_proof(opts)
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

  defp example!(kind), do: Registry.fetch!(kind)

  defp opts_map(opts) when is_map(opts), do: Map.new(opts)
  defp opts_map(opts) when is_list(opts), do: Map.new(opts)
end
