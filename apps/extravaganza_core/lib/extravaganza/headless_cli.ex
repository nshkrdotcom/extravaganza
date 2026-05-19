defmodule Extravaganza.HeadlessCLI do
  @moduledoc """
  Product-owned command dispatcher for local headless examples and Mix tasks.
  """

  alias Extravaganza.HeadlessCLI.{
    Dispatch,
    Errors,
    FixtureContext,
    Guardrails,
    OperationRegistry,
    Output,
    Parser
  }

  alias Extravaganza.HeadlessJSON

  @spec operations() :: [atom()]
  def operations, do: OperationRegistry.operations()

  @doc false
  @spec operation_specs() :: [map()]
  def operation_specs, do: OperationRegistry.operation_specs()

  @spec guardrails_ack_flags() :: [String.t()]
  def guardrails_ack_flags, do: OperationRegistry.guardrails_ack_flags()

  @doc false
  @spec parse_options([String.t()]) :: map()
  def parse_options(argv) when is_list(argv), do: Parser.parse(argv)

  @spec guardrails_acknowledgement_error(atom(), [String.t()]) ::
          nil | {:operator_ack_required, map()}
  def guardrails_acknowledgement_error(operation, argv)
      when is_atom(operation) and is_list(argv) do
    if OperationRegistry.operation?(operation) do
      argv
      |> Parser.parse()
      |> OperationRegistry.maybe_default_live_fixture(operation)
      |> then(&Guardrails.acknowledgement_error(operation, &1))
    end
  end

  @spec run(atom(), [String.t()]) :: :ok
  def run(operation, argv), do: run(operation, argv, %{})

  @spec run(atom(), [String.t()], keyword() | map()) :: :ok
  def run(operation, argv, runtime_opts)
      when is_atom(operation) and is_list(argv) and
             (is_list(runtime_opts) or is_map(runtime_opts)) do
    unless OperationRegistry.operation?(operation) do
      raise ArgumentError, message: inspect(Errors.unsupported_operation(operation))
    end

    opts =
      argv
      |> Parser.parse()
      |> Map.merge(Map.new(runtime_opts))
      |> OperationRegistry.maybe_default_live_fixture(operation)
      |> FixtureContext.apply()

    operation
    |> guarded_dispatch(opts)
    |> print_envelope(operation, opts)
  end

  defp guarded_dispatch(operation, opts) do
    case Guardrails.acknowledgement_error(operation, opts) do
      nil ->
        Dispatch.run(operation, opts)

      reason ->
        HeadlessJSON.error(OperationRegistry.envelope_name(operation), reason, opts)
    end
  end

  defp print_envelope(envelope, _operation, opts) do
    envelope =
      case Map.get(opts, :operation_override) do
        nil -> envelope
        override -> %{envelope | "operation" => Atom.to_string(override)}
      end

    Output.print(envelope, opts)
  end
end
