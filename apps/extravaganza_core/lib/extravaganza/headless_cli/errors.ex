defmodule Extravaganza.HeadlessCLI.Errors do
  @moduledoc false

  @spec unsupported_operation(atom()) :: {:unsupported_operation, atom()}
  def unsupported_operation(operation), do: {:unsupported_operation, operation}
end
