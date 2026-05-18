defmodule Extravaganza.RouteEvidence do
  @moduledoc false

  @spec from_run_detail(map()) :: map()
  def from_run_detail(%{} = data) do
    data
    |> run_detail_parts()
    |> run_detail_route_evidence()
  end

  @spec from_provider_effect(atom(), map(), map(), map(), map() | keyword()) :: map()
  def from_provider_effect(kind, example, proof, provider_effect, opts) do
    provider_effect_route_evidence(%{
      kind: kind,
      example: example,
      proof: proof,
      provider_effect: provider_effect,
      opts: opts_map(opts)
    })
  end

  defp run_detail_parts(data) do
    runtime_row = value(data, "runtime_row") || %{}
    extensions = value(runtime_row, "extensions") || %{}

    %{
      data: data,
      runtime_row: runtime_row,
      governance: value(extensions, "governance") || %{},
      credential_preflight: value(extensions, "credential_preflight") || %{},
      lower_envelope: value(extensions, "lower_envelope") || %{},
      lower_receipt: value(extensions, "lower_receipt") || %{},
      source_publication: value(extensions, "source_publication") || %{}
    }
  end

  defp run_detail_route_evidence(parts) do
    parts
    |> run_identity_refs()
    |> Map.merge(run_authority_refs(parts))
    |> Map.merge(run_lower_refs(parts))
    |> Map.merge(run_projection_refs(parts))
    |> compact()
  end

  defp run_identity_refs(%{data: data, runtime_row: runtime_row, governance: governance}) do
    run_ref = value(data, "run_ref") || value(runtime_row, "run_ref")
    trace_ref = value(data, "trace_ref") || generated_ref("trace", run_ref)

    %{
      "product_role_ref" =>
        value(governance, "product_role_ref") ||
          "runtime-role://extravaganza/coding-agent-runtime",
      "binding_ref" =>
        value(governance, "binding_ref") ||
          value(governance, "runtime_binding_ref") ||
          "runtime-binding://extravaganza/coding-agent-runtime",
      "manifest_ref" =>
        value(governance, "manifest_ref") || value(governance, "connector_manifest_ref"),
      "connector_manifest_ref" => value(governance, "connector_manifest_ref"),
      "trace_ref" => trace_ref,
      "trace_replay" => replay_not_emitted(trace_ref)
    }
  end

  defp run_authority_refs(%{governance: governance, credential_preflight: credential_preflight}) do
    %{
      "authority_ref" => value(governance, "authority_ref"),
      "decision_ref" => value(governance, "decision_ref"),
      "connector_binding_ref" => value(governance, "connector_binding_ref"),
      "credential_lease_ref" => value(credential_preflight, "credential_lease_ref")
    }
  end

  defp run_lower_refs(%{lower_envelope: lower_envelope, lower_receipt: lower_receipt}) do
    lower_receipt_ref = value(lower_receipt, "lower_receipt_ref")

    %{
      "lower_request_ref" => value(lower_envelope, "lower_request_ref"),
      "lower_receipt_ref" => lower_receipt_ref,
      "receipt_ref" => lower_receipt_ref
    }
  end

  defp run_projection_refs(%{
         data: data,
         runtime_row: runtime_row,
         source_publication: source_publication
       }) do
    run_ref = value(data, "run_ref") || value(runtime_row, "run_ref")

    %{
      "source_publication_ref" => value(source_publication, "source_publication_receipt_ref"),
      "projection_ref" =>
        value(source_publication, "projection_ref") || generated_ref("projection", run_ref),
      "evidence_ref" =>
        value(source_publication, "evidence_ref") || generated_ref("evidence", run_ref)
    }
  end

  defp provider_effect_route_evidence(%{
         kind: kind,
         example: example,
         proof: proof,
         provider_effect: provider_effect,
         opts: opts
       }) do
    trace_ref = string_value(opts, :trace_ref) || string_value(opts, :trace_id)

    %{kind: kind, example: example, proof: proof, provider_effect: provider_effect, opts: opts}
    |> provider_identity_refs()
    |> Map.merge(provider_authority_refs(proof, provider_effect, opts))
    |> Map.merge(provider_lower_refs(provider_effect))
    |> Map.merge(provider_projection_refs(kind, example, provider_effect))
    |> Map.merge(%{"trace_ref" => trace_ref, "trace_replay" => replay_not_emitted(trace_ref)})
    |> compact()
  end

  defp provider_identity_refs(%{kind: kind, example: example, provider_effect: provider_effect}) do
    %{
      "product_role_ref" => product_role_ref(kind),
      "binding_ref" => binding_ref(kind, provider_effect),
      "manifest_ref" => manifest_ref(example, provider_effect),
      "connector_manifest_ref" => connector_manifest_ref(example, provider_effect),
      "operation_ref" => value(provider_effect, "operation") || Map.get(example, :operation),
      "operation_receipt_refs" => operation_receipt_refs(provider_effect)
    }
  end

  defp provider_authority_refs(proof, provider_effect, opts) do
    %{
      "authority_ref" =>
        value(provider_effect, "authority_handoff_ref") || value(proof, "authority_ref"),
      "authority_packet_ref" => value(provider_effect, "authority_packet_ref"),
      "connector_binding_ref" => value(provider_effect, "connector_binding_ref"),
      "credential_lease_ref" =>
        value(provider_effect, "credential_lease_ref") ||
          string_value(opts, :credential_lease_ref)
    }
  end

  defp provider_lower_refs(provider_effect) do
    lower_receipt_ref = value(provider_effect, "lower_receipt_ref")
    lower_denial_ref = value(provider_effect, "lower_denial_ref")

    %{
      "lower_request_ref" => value(provider_effect, "lower_request_ref"),
      "lower_receipt_ref" => lower_receipt_ref,
      "lower_denial_ref" => lower_denial_ref,
      "receipt_ref" =>
        first_present([
          lower_receipt_ref,
          lower_denial_ref,
          value(provider_effect, "source_publication_ref"),
          value(provider_effect, "evidence_ref"),
          value(provider_effect, "receipt_ref")
        ])
    }
  end

  defp provider_projection_refs(kind, example, provider_effect) do
    %{
      "projection_ref" => projection_ref(kind, example, provider_effect),
      "evidence_ref" => evidence_ref(kind, provider_effect)
    }
  end

  @spec from_live_smoke(map(), map() | keyword()) :: map()
  def from_live_smoke(examples, opts) when is_map(examples) do
    opts = opts_map(opts)
    trace_ref = string_value(opts, :trace_ref) || string_value(opts, :trace_id)

    nested =
      examples
      |> Enum.map(fn {operation, payload} ->
        {operation,
         value(payload, "route_evidence") ||
           value(value(payload, "provider_effect"), "route_evidence")}
      end)
      |> Enum.reject(fn {_operation, route} -> route in [nil, %{}] end)
      |> Map.new()

    %{
      "product_role_ref" => "product-role://extravaganza/live-smoke",
      "binding_ref" => "proof-binding://extravaganza/live-smoke",
      "projection_ref" => "projection://extravaganza/live-smoke",
      "evidence_ref" => "evidence://extravaganza/live-smoke",
      "trace_ref" => trace_ref,
      "trace_replay" => replay_not_emitted(trace_ref),
      "examples" => nested
    }
    |> compact()
  end

  @spec put_operation_receipts(map()) :: map()
  def put_operation_receipts(%{"operation_receipts" => receipts} = provider_effect)
      when is_list(receipts) and receipts != [] do
    provider_effect
  end

  def put_operation_receipts(%{} = provider_effect) do
    lower_request_ref = value(provider_effect, "lower_request_ref")
    lower_receipt_ref = value(provider_effect, "lower_receipt_ref")
    lower_denial_ref = value(provider_effect, "lower_denial_ref")

    receipt =
      %{
        "operation_ref" => value(provider_effect, "operation"),
        "capability_id" => value(provider_effect, "operation"),
        "authority_ref" => value(provider_effect, "authority_handoff_ref"),
        "authority_packet_ref" => value(provider_effect, "authority_packet_ref"),
        "connector_binding_ref" => value(provider_effect, "connector_binding_ref"),
        "credential_lease_ref" => value(provider_effect, "credential_lease_ref"),
        "lower_request_ref" => lower_request_ref,
        "lower_receipt_ref" => lower_receipt_ref,
        "lower_denial_ref" => lower_denial_ref,
        "status" => value(provider_effect, "status")
      }
      |> compact()

    if route_receipt?(receipt) do
      Map.put(provider_effect, "operation_receipts", [receipt])
    else
      provider_effect
    end
  end

  defp route_receipt?(receipt) do
    Enum.any?(
      ["lower_request_ref", "lower_receipt_ref", "lower_denial_ref"],
      &present?(value(receipt, &1))
    )
  end

  defp product_role_ref(:linear_source), do: "source-role://extravaganza/issue-tracker"
  defp product_role_ref(:linear_current_states), do: "source-role://extravaganza/issue-tracker"

  defp product_role_ref(:linear_publication),
    do: "publication-role://extravaganza/source-publication"

  defp product_role_ref(:linear_graphql_tool), do: "tool-role://extravaganza/issue-graphql-tool"
  defp product_role_ref(:codex_turn), do: "runtime-role://extravaganza/coding-agent-runtime"

  defp product_role_ref(:github_evidence),
    do: "evidence-role://extravaganza/proposed-change-evidence"

  defp product_role_ref(:github_pr_cleanup),
    do: "resource-effect-role://extravaganza/proposed-change-cleanup"

  defp product_role_ref(kind), do: "product-role://extravaganza/#{kind}"

  defp binding_ref(:linear_source, provider_effect),
    do:
      "source-binding://extravaganza/#{value(provider_effect, "source_binding_id") || "linear-primary"}"

  defp binding_ref(:linear_current_states, provider_effect),
    do:
      "source-binding://extravaganza/#{value(provider_effect, "source_binding_id") || "linear-primary"}"

  defp binding_ref(:linear_publication, provider_effect),
    do:
      "source-binding://extravaganza/#{value(provider_effect, "source_binding_id") || "linear-primary"}"

  defp binding_ref(:linear_graphql_tool, _provider_effect),
    do: "tool-binding://extravaganza/issue-graphql-tool"

  defp binding_ref(:codex_turn, _provider_effect),
    do: "runtime-binding://extravaganza/coding-agent-runtime"

  defp binding_ref(:github_evidence, _provider_effect),
    do: "evidence-binding://extravaganza/proposed-change-evidence"

  defp binding_ref(:github_pr_cleanup, _provider_effect),
    do: "resource-effect-binding://extravaganza/proposed-change-cleanup"

  defp binding_ref(kind, _provider_effect), do: "binding://extravaganza/#{kind}"

  defp manifest_ref(example, provider_effect) do
    connector_manifest_ref(example, provider_effect) ||
      "manifest://jido/connectors/#{Map.get(example, :provider)}@live"
  end

  defp connector_manifest_ref(example, provider_effect) do
    first_present([
      first_operation_receipt_ref(provider_effect, "connector_manifest_ref"),
      value(provider_effect, "connector_manifest_ref"),
      "manifest://jido/connectors/#{Map.get(example, :provider)}@live"
    ])
  end

  defp projection_ref(:github_evidence, _example, provider_effect),
    do: value(provider_effect, "evidence_ref")

  defp projection_ref(_kind, example, provider_effect) do
    first_present([
      value(provider_effect, "source_publication_ref"),
      value(provider_effect, "evidence_ref"),
      generated_ref("projection", Map.get(example, :operation))
    ])
  end

  defp evidence_ref(:github_evidence, provider_effect), do: value(provider_effect, "evidence_ref")
  defp evidence_ref(_kind, provider_effect), do: value(provider_effect, "source_publication_ref")

  defp operation_receipt_refs(provider_effect) do
    provider_effect
    |> value("operation_receipts")
    |> List.wrap()
    |> Enum.map(&operation_receipt_ref/1)
    |> Enum.reject(&is_nil/1)
  end

  defp operation_receipt_ref(receipt) do
    first_present([
      value(receipt, "lower_receipt_ref"),
      value(receipt, "lower_denial_ref"),
      value(receipt, "lower_request_ref")
    ])
  end

  defp first_operation_receipt_ref(provider_effect, key) do
    provider_effect
    |> value("operation_receipts")
    |> List.wrap()
    |> Enum.find_value(&value(&1, key))
  end

  defp replay_not_emitted(nil) do
    %{
      "status" => "not_emitted",
      "replay_system_ref" => "ai_trace",
      "reason" => "route_replay_event_not_exported_by_headless_command"
    }
  end

  defp replay_not_emitted(trace_ref) do
    %{
      "status" => "not_emitted",
      "replay_system_ref" => "ai_trace",
      "trace_ref" => trace_ref,
      "reason" => "route_replay_event_not_exported_by_headless_command"
    }
  end

  defp generated_ref(_kind, nil), do: nil

  defp generated_ref(kind, value) do
    "#{kind}://extravaganza/#{safe_suffix(value)}"
  end

  defp safe_suffix(value) when is_atom(value), do: value |> Atom.to_string() |> safe_suffix()

  defp safe_suffix(value) when is_binary(value) do
    value
    |> String.replace("://", ":")
    |> String.replace("/", ":")
    |> String.replace(".", "-")
    |> String.replace("_", "-")
  end

  defp safe_suffix(value), do: value |> to_string() |> safe_suffix()

  defp opts_map(opts) when is_list(opts), do: Map.new(opts)
  defp opts_map(opts) when is_map(opts), do: opts

  defp first_present(values), do: Enum.find(values, &present?/1)

  defp present?(value) when value in [nil, "", [], %{}], do: false
  defp present?(_value), do: true

  defp compact(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", [], %{}] end)
    |> Map.new()
  end

  defp string_value(map, key) do
    case value(map, key) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      _other -> nil
    end
  end

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
end
