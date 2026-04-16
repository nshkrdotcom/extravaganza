defmodule ExtravaganzaWeb.PageController do
  use ExtravaganzaWeb, :controller

  alias Extravaganza.Queries

  def home(conn, _params) do
    render(conn, :home,
      identity: Extravaganza.identity(),
      mission: Extravaganza.mission(),
      role_label: "proving-ground product"
    )
  end

  def queue(conn, params) do
    case Queries.operator_queue(params) do
      {:ok, queue} ->
        render(conn, :queue,
          queue_entries: queue.page.entries,
          queue_stats: queue.stats,
          queue_total_count: queue.page.total_count,
          queue_has_more?: queue.page.has_more,
          queue_next_cursor: queue.page.next_cursor,
          queue_error: nil
        )

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> render(:queue,
          queue_entries: [],
          queue_stats: %{},
          queue_total_count: 0,
          queue_has_more?: false,
          queue_next_cursor: nil,
          queue_error: inspect(reason)
        )
    end
  end
end
