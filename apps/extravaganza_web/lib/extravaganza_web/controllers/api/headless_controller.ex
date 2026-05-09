defmodule ExtravaganzaWeb.Api.HeadlessController do
  use ExtravaganzaWeb, :controller

  alias Extravaganza.{HeadlessJSON, HeadlessSurface}

  alias Extravaganza.Presenters.{
    CommandResultPresenter,
    EventPresenter,
    EvidencePresenter,
    LeasePresenter,
    ReviewPresenter,
    RunPresenter,
    StatePresenter,
    SubjectPresenter
  }

  @status_by_code %{
    "not_found" => :not_found,
    "runtime_projection_not_found" => :not_found,
    "bad_request" => :bad_request,
    "invalid_action" => :unprocessable_entity,
    "action_denied" => :forbidden,
    "unauthorized_lower_read" => :forbidden,
    "archived" => :gone,
    "snapshot_timeout" => :service_unavailable,
    "unavailable" => :service_unavailable,
    "method_not_allowed" => :method_not_allowed,
    "internal_error" => :internal_server_error
  }

  def state(conn, params) do
    case HeadlessSurface.state_snapshot(params) do
      {:ok, snapshot} ->
        render_success(conn, :state, StatePresenter.present(snapshot, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def subject(conn, %{"subject_id" => subject_id} = params) do
    case HeadlessSurface.subject_detail(subject_id, params) do
      {:ok, detail} ->
        render_success(conn, :subject, SubjectPresenter.present(detail, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def issue_subject(conn, %{"issue_identifier" => issue_identifier} = params) do
    case HeadlessSurface.subject_by_issue_identifier(issue_identifier, params) do
      {:ok, detail} ->
        render_success(conn, :subject, SubjectPresenter.present(detail, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def run(conn, %{"run_id" => run_id} = params) do
    case HeadlessSurface.run_detail(run_id, params) do
      {:ok, detail} ->
        render_success(conn, :run, RunPresenter.present(detail, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def refresh(conn, params) do
    case HeadlessSurface.request_refresh(params) do
      {:ok, result} ->
        render_success(
          conn,
          :refresh,
          CommandResultPresenter.present(result, presenter_opts(conn))
        )

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def control(conn, %{"subject_id" => subject_id, "action" => action} = params) do
    case HeadlessSurface.request_control(subject_id, action, params) do
      {:ok, result} ->
        render_success(
          conn,
          :control,
          CommandResultPresenter.present(result, presenter_opts(conn))
        )

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def read_lease(conn, %{"subject_id" => subject_id}) do
    case HeadlessSurface.issue_read_lease(subject_id) do
      {:ok, lease} ->
        render_success(conn, :read_lease, LeasePresenter.present(lease, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def stream_attach_lease(conn, %{"subject_id" => subject_id}) do
    case HeadlessSurface.issue_stream_attach_lease(subject_id) do
      {:ok, lease} ->
        render_success(
          conn,
          :stream_attach_lease,
          LeasePresenter.present(lease, presenter_opts(conn))
        )

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def reviews(conn, params) do
    case HeadlessSurface.list_reviews(params) do
      {:ok, reviews_page} ->
        render_success(
          conn,
          :reviews,
          ReviewPresenter.present_page(reviews_page, presenter_opts(conn))
        )

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def review_decision(conn, %{"decision_id" => decision_id, "decision" => decision} = params) do
    review_identity = %{
      id: decision_id,
      decision_kind: Map.get(params, "decision_kind"),
      subject_id: Map.get(params, "subject_id"),
      subject_kind: Map.get(params, "subject_kind")
    }

    case HeadlessSurface.record_review_decision(review_identity, %{
           decision: decision,
           reason: Map.get(params, "reason")
         }) do
      {:ok, result} ->
        render_success(
          conn,
          :review,
          CommandResultPresenter.present(result, presenter_opts(conn))
        )

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def evidence(conn, %{"run_id" => run_id} = params) do
    case HeadlessSurface.evidence_chain(run_id, params) do
      {:ok, evidence} ->
        render_success(conn, :evidence, EvidencePresenter.present(evidence, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def events(conn, params) do
    case HeadlessSurface.events(params) do
      {:ok, events} ->
        render_success(conn, :events, EventPresenter.present_page(events, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  defp render_success(conn, operation, data) do
    json(conn, HeadlessJSON.success(operation, data, presenter_opts(conn)))
  end

  defp render_error(conn, reason) do
    {code, _message} = error_code(reason)

    conn
    |> put_status(Map.fetch!(@status_by_code, code))
    |> json(HeadlessJSON.error(:headless_api, reason, presenter_opts(conn)))
  end

  defp error_code(:not_found), do: {"not_found", "Subject not found"}

  defp error_code(:runtime_projection_not_found),
    do: {"runtime_projection_not_found", "Runtime projection not found"}

  defp error_code(:invalid_action), do: {"invalid_action", "Invalid action"}
  defp error_code(:action_denied), do: {"action_denied", "Action denied"}

  defp error_code(:unauthorized_lower_read),
    do: {"unauthorized_lower_read", "Unauthorized lower read"}

  defp error_code(:archived), do: {"archived", "Archived"}
  defp error_code(:snapshot_timeout), do: {"snapshot_timeout", "Snapshot timeout"}
  defp error_code(:unavailable), do: {"unavailable", "Unavailable"}
  defp error_code(:method_not_allowed), do: {"method_not_allowed", "Method not allowed"}
  defp error_code(:bad_request), do: {"bad_request", "Bad request"}
  defp error_code(_reason), do: {"internal_error", "Internal error"}

  defp presenter_opts(conn) do
    [
      correlation_id: conn.assigns[:correlation_id],
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    ]
  end
end
