defmodule Extravaganza.HeadlessLiveExamples.Credentials do
  @moduledoc false

  @linear_kinds [
    :linear_source,
    :linear_current_states,
    :linear_publication,
    :linear_graphql_tool
  ]

  @app_config_kinds [:codex_turn, :github_evidence, :github_pr_cleanup]

  @spec preflight(atom(), map(), map()) :: map()
  def preflight(kind, example, opts) when is_atom(kind) and is_map(example) and is_map(opts) do
    connection_id = string_value(opts, :connection_id)
    credential_ref = string_value(opts, :credential_ref)
    credential_lease_ref = string_value(opts, :credential_lease_ref)
    stdin? = truthy?(Map.get(opts, :api_key_stdin?))
    available? = truthy?(Map.get(opts, :credential_available?))

    %{
      "provider" => Map.fetch!(example, :provider),
      "status" => preflight_status(kind, opts, connection_id, stdin?, available?),
      "dispatch_binding" => dispatch_binding(kind, opts),
      "connection_id" => connection_id,
      "credential_ref" => credential_ref,
      "credential_lease_ref" => credential_lease_ref,
      "credential_source" => source(kind, opts),
      "secret_material_present?" => stdin?,
      "secret_material_redacted?" => true
    }
    |> compact_map()
  end

  @spec skip_reason(atom(), map(), map()) :: map()
  def skip_reason(kind, example, opts) when is_atom(kind) and is_map(example) and is_map(opts) do
    cond do
      ref_present?(opts) ->
        %{
          "code" => "credential_ref_requires_connection_id",
          "provider" => Map.fetch!(example, :provider),
          "credential_refs" => Map.fetch!(example, :credential_refs),
          "detail" =>
            "explicit credential refs are redacted metadata; provider dispatch requires the lower connection_id binding"
        }

      not live_product_path?(opts) and supplied?(kind, opts) ->
        %{
          "code" => "live_product_path_required",
          "provider" => Map.fetch!(example, :provider),
          "credential_refs" => Map.fetch!(example, :credential_refs),
          "detail" =>
            "credential input was accepted only as redacted preflight metadata; live provider dispatch requires --live-product-path"
        }

      supplied?(kind, opts) ->
        %{
          "code" => "live_provider_effect_deferred",
          "provider" => Map.fetch!(example, :provider),
          "detail" =>
            "product command exercised the headless live example entrypoint; live provider effect remains gated to the owner lower bridge"
        }

      true ->
        %{
          "code" => "credential_not_supplied_to_product_command",
          "provider" => Map.fetch!(example, :provider),
          "credential_refs" => Map.fetch!(example, :credential_refs)
        }
    end
  end

  @spec supplied?(atom(), map()) :: boolean()
  def supplied?(kind, opts) when kind in @linear_kinds do
    truthy?(Map.get(opts, :api_key_stdin?)) or truthy?(Map.get(opts, :credential_available?)) or
      present?(string_value(opts, :connection_id))
  end

  def supplied?(kind, opts) when kind in @app_config_kinds do
    truthy?(Map.get(opts, :credential_available?)) or truthy?(Map.get(opts, :live_product_path?)) or
      present?(string_value(opts, :connection_id))
  end

  def supplied?(_kind, opts) do
    truthy?(Map.get(opts, :credential_available?)) or
      present?(string_value(opts, :connection_id))
  end

  @spec ref_present?(map()) :: boolean()
  def ref_present?(opts) do
    not present?(string_value(opts, :connection_id)) and
      (present?(string_value(opts, :credential_ref)) or
         present?(string_value(opts, :credential_lease_ref)))
  end

  @spec live_product_path?(map()) :: boolean()
  def live_product_path?(opts), do: truthy?(Map.get(opts, :live_product_path?))

  @spec deterministic_fixture?(map()) :: boolean()
  def deterministic_fixture?(opts), do: not live_product_path?(opts)

  defp preflight_status(kind, opts, connection_id, stdin?, available?) do
    cond do
      ref_present?(opts) ->
        "missing_dispatch_binding"

      deterministic_supplied?(kind, opts) ->
        "requires_live_product_path"

      deterministic_fixture?(opts) ->
        "fixture_only"

      dispatchable?(kind, opts, connection_id, stdin?, available?) ->
        "dispatchable"

      true ->
        "missing"
    end
  end

  defp deterministic_supplied?(kind, opts),
    do: deterministic_fixture?(opts) and supplied?(kind, opts)

  defp dispatchable?(kind, opts, connection_id, stdin?, available?) do
    present?(connection_id) or stdin? or available? or app_config?(kind, opts)
  end

  defp app_config?(kind, opts),
    do: kind in @app_config_kinds and live_product_path?(opts)

  defp dispatch_binding(kind, opts) do
    cond do
      present?(string_value(opts, :connection_id)) ->
        "connection_id"

      truthy?(Map.get(opts, :api_key_stdin?)) ->
        "ephemeral_stdin"

      truthy?(Map.get(opts, :credential_available?)) ->
        "external_harness"

      kind in @app_config_kinds and truthy?(Map.get(opts, :live_product_path?)) ->
        "app_config"

      true ->
        nil
    end
  end

  defp source(kind, opts) do
    cond do
      truthy?(Map.get(opts, :api_key_stdin?)) ->
        "stdin"

      present?(string_value(opts, :connection_id)) ->
        "connection_id"

      truthy?(Map.get(opts, :credential_available?)) ->
        "external_harness"

      kind in @app_config_kinds and truthy?(Map.get(opts, :live_product_path?)) ->
        "app_config"

      present?(string_value(opts, :credential_ref)) ->
        "credential_ref"

      present?(string_value(opts, :credential_lease_ref)) ->
        "credential_lease_ref"

      true ->
        nil
    end
  end

  defp string_value(map, key) do
    case value(map, key) do
      value when is_binary(value) and value != "" -> value
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      _other -> nil
    end
  end

  defp value(%{} = map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp value(_value, _key), do: nil

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
  defp truthy?(value), do: value in [true, "true", 1, "1"]

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", [], %{}] end)
    |> Map.new()
  end
end
