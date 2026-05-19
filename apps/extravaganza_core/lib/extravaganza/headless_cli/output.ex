defmodule Extravaganza.HeadlessCLI.Output do
  @moduledoc false

  @spec print(map(), keyword() | map()) :: :ok
  def print(envelope, opts) when is_map(envelope) do
    encoded = Jason.encode!(envelope, pretty: Map.get(opts, :pretty?, true))

    Mix.shell().info(encoded)
  end
end
