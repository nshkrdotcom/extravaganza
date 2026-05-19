defmodule Extravaganza.HeadlessLiveExamples.Envelope do
  @moduledoc false

  alias Extravaganza.HeadlessLiveExamples.Credentials
  alias Extravaganza.RouteEvidence

  @spec example_payload(atom(), map(), map(), map(), map()) :: map()
  def example_payload(kind, example, proof, opts, provider_effect)
      when is_atom(kind) and is_map(example) and is_map(proof) and is_map(opts) and
             is_map(provider_effect) do
    credential_preflight = Credentials.preflight(kind, example, opts)

    payload =
      proof
      |> common_refs()
      |> provider_effect_refs(provider_effect)
      |> Map.merge(%{
        "status" => example_status(provider_effect),
        "operation" => Map.fetch!(example, :operation),
        "trace_id" => live_trace_id(opts, Map.fetch!(example, :operation)),
        "receipt_ref" => live_receipt_ref(Map.fetch!(example, :operation), proof),
        "receipt_state" => "recorded",
        "provider" => Map.fetch!(example, :provider),
        "capability_ids" => Map.fetch!(example, :capability_ids),
        "credential_refs" => Map.fetch!(example, :credential_refs),
        "credential_preflight" => credential_preflight,
        "command" => Map.fetch!(example, :command),
        "product_path_exercised?" => true,
        "product_path" =>
          product_path(proof, Map.fetch!(example, :product_entrypoint), provider_effect),
        "route_evidence" => Map.get(provider_effect, "route_evidence"),
        "provider_effect" => provider_effect
      })
      |> Map.merge(example_mode_fields(opts, provider_effect))

    payload
    |> maybe_put("source_publication_ref", Map.get(provider_effect, "source_publication_ref"))
    |> maybe_put("lower_request_ref", Map.get(provider_effect, "lower_request_ref"))
    |> maybe_put("lower_receipt_ref", Map.get(provider_effect, "lower_receipt_ref"))
  end

  @spec smoke_payload(map(), map(), map(), map(), String.t(), map()) :: map()
  def smoke_payload(proof, examples, summary, opts, trace_id, deterministic_matrix)
      when is_map(proof) and is_map(examples) and is_map(summary) and is_map(opts) do
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
      "deterministic_memory_tracker_matrix" => deterministic_matrix
    })
    |> Map.merge(example_mode_fields(opts, summary))
    |> maybe_put("source_publication_ref", aggregate_source_publication_ref(examples))
    |> Map.merge(summary)
  end

  @spec aggregate_summary(map(), [map()]) :: map()
  def aggregate_summary(examples, required_examples) when is_map(examples) do
    required_operations = Enum.map(required_examples, &Map.fetch!(&1, :operation))
    completed_operations = operations_with_status(required_operations, examples, "completed")
    skipped_operations = operations_with_status(required_operations, examples, "skipped")
    failed_operations = operations_with_status(required_operations, examples, "failed")

    %{
      "required_operations" => required_operations,
      "completed_operations" => completed_operations,
      "skipped_operations" => skipped_operations,
      "failed_operations" => failed_operations,
      "provider_effect_count" => map_size(examples),
      "all_provider_effects_completed?" => failed_operations == [] and skipped_operations == []
    }
  end

  @spec annotate_provider_effect(map(), map()) :: map()
  def annotate_provider_effect(provider_effect, opts) do
    Map.merge(provider_effect, %{
      "deterministic_fixture?" => Credentials.deterministic_fixture?(opts),
      "fixture_backed?" => Credentials.deterministic_fixture?(opts),
      "live_product_path?" => Credentials.live_product_path?(opts),
      "live_provider_effect?" =>
        Credentials.live_product_path?(opts) and live_provider_effect_recorded?(provider_effect)
    })
  end

  @spec product_readback_confirmed?(map()) :: boolean()
  def product_readback_confirmed?(proof), do: Map.get(proof, "readback_count", 0) > 0

  defp example_status(%{"status" => "receipt_recorded"}), do: "completed"
  defp example_status(%{"status" => "governed_denial_recorded"}), do: "completed"
  defp example_status(%{"status" => "failed"}), do: "failed"
  defp example_status(_provider_effect), do: "skipped"

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
    live_product_path? = Credentials.live_product_path?(opts)

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

  defp live_provider_effect_recorded?(%{"all_provider_effects_completed?" => true}), do: true

  defp live_provider_effect_recorded?(%{"status" => status})
       when status in ["receipt_recorded", "governed_denial_recorded"],
       do: true

  defp live_provider_effect_recorded?(%{"provider_request_sent?" => true}), do: true
  defp live_provider_effect_recorded?(_value), do: false

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
    Enum.find_value(examples, fn {_operation, payload} ->
      case Map.get(payload, "source_publication_ref") do
        value when is_binary(value) and value != "" -> value
        _other -> nil
      end
    end)
  end

  defp live_trace_id(opts, operation) do
    Map.get(opts, :trace_id) ||
      "trace://extravaganza/#{operation}/#{System.unique_integer([:positive])}"
  end

  defp live_smoke_correlation_ref(trace_id), do: "live-smoke://#{ref_suffix(trace_id)}"

  defp live_receipt_ref(operation, proof) do
    suffix = proof |> Map.fetch!("run_ref") |> ref_suffix()
    "receipt://extravaganza/#{operation}/#{suffix}"
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp value(%_{} = struct, key), do: struct |> Map.from_struct() |> value(key)

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
end
