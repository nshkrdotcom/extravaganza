defmodule ExtravaganzaWeb.Plugs.AssignCorrelationId do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    correlation_id =
      get_req_header(conn, "x-correlation-id")
      |> List.first()
      |> case do
        value when is_binary(value) and value != "" -> value
        _ -> "corr:extravaganza:#{System.unique_integer([:positive])}"
      end

    assign(conn, :correlation_id, correlation_id)
  end
end
