defmodule ExtravaganzaWeb.PageController do
  use ExtravaganzaWeb, :controller

  alias Extravaganza.{Queries, Reviews}

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

  def reviews(conn, params) do
    case Queries.pending_reviews(params) do
      {:ok, reviews_page} ->
        render(conn, :reviews,
          review_entries: reviews_page.page.entries,
          review_total_count: reviews_page.page.total_count,
          review_has_more?: reviews_page.page.has_more,
          review_next_cursor: reviews_page.page.next_cursor,
          review_error: nil
        )

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> render(:reviews,
          review_entries: [],
          review_total_count: 0,
          review_has_more?: false,
          review_next_cursor: nil,
          review_error: inspect(reason)
        )
    end
  end

  def accept_review(conn, %{"decision_id" => decision_id} = params) do
    case Reviews.record_pending_decision(
           %{
             id: decision_id,
             decision_kind: Map.get(params, "decision_kind"),
             subject_id: Map.get(params, "subject_id"),
             subject_kind: Map.get(params, "subject_kind")
           },
           %{
             decision: :accept,
             reason: Map.get(params, "reason")
           }
         ) do
      {:ok, result} ->
        conn
        |> put_flash(:info, result.message || "Review accepted")
        |> redirect(to: ~p"/reviews")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Review failed: #{inspect(reason)}")
        |> redirect(to: ~p"/reviews")
    end
  end
end
