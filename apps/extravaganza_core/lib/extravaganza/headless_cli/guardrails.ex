defmodule Extravaganza.HeadlessCLI.Guardrails do
  @moduledoc false

  alias Extravaganza.HeadlessCLI.OperationRegistry

  @spec acknowledgement_error(atom(), map()) :: nil | {:operator_ack_required, map()}
  def acknowledgement_error(operation, opts) when is_atom(operation) and is_map(opts) do
    if ack_required?(operation, opts) and not truthy?(Map.get(opts, :guardrails_ack?)) do
      {:operator_ack_required,
       %{
         operation: OperationRegistry.envelope_name(operation),
         required_flags: OperationRegistry.guardrails_ack_flags(),
         legacy_flag_supported?: true,
         reason: ack_reason(operation, opts)
       }}
    end
  end

  defp ack_required?(operation, opts) do
    cond do
      deterministic_fixture_without_live_path?(opts) ->
        false

      OperationRegistry.live_operation?(operation) and truthy?(Map.get(opts, :live_product_path?)) ->
        true

      OperationRegistry.mutating_operation?(operation) ->
        true

      true ->
        false
    end
  end

  defp deterministic_fixture_without_live_path?(opts),
    do: Map.has_key?(opts, :fixture) and not truthy?(Map.get(opts, :live_product_path?))

  defp ack_reason(operation, opts) do
    cond do
      OperationRegistry.live_operation?(operation) and truthy?(Map.get(opts, :live_product_path?)) ->
        "live_product_path"

      OperationRegistry.mutating_operation?(operation) ->
        "mutating_command"

      true ->
        "headless_guardrail"
    end
  end

  defp truthy?(value), do: value not in [nil, false]
end
