defmodule Extravaganza.Queries do
  @moduledoc """
  Product-local read facade over operator-facing AppKit surfaces.
  """

  alias AppKit.OperatorSurface
  alias Extravaganza.{Config, ProductSurface}

  @spec run_status(AppKit.Core.RunRef.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_status(run_ref, attrs \\ %{}, opts \\ []) when is_map(attrs) and is_list(opts) do
    config = Config.load(opts)
    OperatorSurface.run_status(run_ref, attrs, ProductSurface.operator_opts(config, opts))
  end
end
