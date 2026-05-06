defmodule ExtravaganzaWeb.PageController do
  use ExtravaganzaWeb, :controller

  alias AppKit.OperatorConsole
  alias Extravaganza.Presenters.{ReviewPresenter, StatePresenter, SubjectPresenter}
  alias Extravaganza.ProductHost

  def home(conn, _params) do
    render(conn, :home,
      identity: Extravaganza.identity(),
      mission: Extravaganza.mission(),
      role_label: "proving-ground product"
    )
  end

  def queue(conn, params) do
    case ProductHost.operator_queue(params) do
      {:ok, queue} ->
        presented = StatePresenter.present_queue(queue)

        render(conn, :queue,
          queue_entries: presented.entries,
          queue_stats: presented.stats,
          queue_total_count: presented.total_count,
          queue_has_more?: presented.has_more?,
          queue_next_cursor: presented.next_cursor,
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
    case ProductHost.pending_reviews(params) do
      {:ok, reviews_page} ->
        presented = ReviewPresenter.present_page(reviews_page)
        page = presented["data"]["page"]

        render(conn, :reviews,
          review_entries: reviews_page.page.entries,
          review_total_count: page["total_entries"],
          review_has_more?: reviews_page.page.has_more,
          review_next_cursor: page["cursor"],
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

  def operator_console(conn, _params) do
    with {:ok, session} <- OperatorConsole.authorize(operator_console_session()),
         {:ok, console} <- OperatorConsole.render(session, operator_console_sections()) do
      render(conn, :operator_console, console: console, console_error: nil)
    else
      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> render(:operator_console, console: nil, console_error: inspect(reason))
    end
  end

  def subject(conn, %{"subject_id" => subject_id}) do
    render_subject(conn, subject_id, %{})
  end

  def apply_subject_action(conn, %{"subject_id" => subject_id, "action" => action} = params) do
    case ProductHost.apply_subject_action(subject_id, action, subject_action_params(params)) do
      {:ok, result} ->
        conn
        |> put_flash(:info, result.message || "Action completed")
        |> redirect(to: ~p"/subjects/#{subject_id}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Action failed: #{inspect(reason)}")
        |> redirect(to: ~p"/subjects/#{subject_id}")
    end
  end

  def issue_read_lease(conn, %{"subject_id" => subject_id}) do
    case ProductHost.issue_read_lease(subject_id) do
      {:ok, read_lease} ->
        render_subject(conn, subject_id, %{read_lease: read_lease})

      {:error, reason} ->
        conn
        |> put_flash(:error, "Read lease failed: #{inspect(reason)}")
        |> redirect(to: ~p"/subjects/#{subject_id}")
    end
  end

  def issue_stream_attach_lease(conn, %{"subject_id" => subject_id}) do
    case ProductHost.issue_stream_attach_lease(subject_id) do
      {:ok, stream_attach_lease} ->
        render_subject(conn, subject_id, %{stream_attach_lease: stream_attach_lease})

      {:error, reason} ->
        conn
        |> put_flash(:error, "Stream attach lease failed: #{inspect(reason)}")
        |> redirect(to: ~p"/subjects/#{subject_id}")
    end
  end

  def record_review_decision(
        conn,
        %{"decision_id" => decision_id, "decision" => decision} = params
      ) do
    case ProductHost.record_review_decision(
           %{
             id: decision_id,
             decision_kind: Map.get(params, "decision_kind"),
             subject_id: Map.get(params, "subject_id"),
             subject_kind: Map.get(params, "subject_kind")
           },
           %{
             decision: decision,
             reason: Map.get(params, "reason")
           }
         ) do
      {:ok, result} ->
        conn
        |> put_flash(:info, result.message || "Review decision recorded")
        |> redirect(to: ~p"/reviews")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Review failed: #{inspect(reason)}")
        |> redirect(to: ~p"/reviews")
    end
  end

  defp render_subject(conn, subject_id, extra_assigns) when is_map(extra_assigns) do
    case ProductHost.subject_detail(subject_id) do
      {:ok, detail} ->
        presented = SubjectPresenter.present(detail, extra_assigns: extra_assigns)

        assigns = %{
          subject: presented.subject,
          subject_actions: presented.actions,
          subject_timeline: presented.timeline,
          unified_trace: presented.unified_trace,
          lineage_summary: presented.lineage_summary,
          trace_error: presented.trace_error,
          read_lease: presented.read_lease,
          stream_attach_lease: presented.stream_attach_lease
        }

        render(conn, :subject, assigns)

      {:error, reason} ->
        conn
        |> put_flash(:error, "Subject view unavailable: #{inspect(reason)}")
        |> redirect(to: ~p"/queue")
    end
  end

  defp subject_action_params(params) when is_map(params) do
    Map.drop(params, ["_csrf_token", "action", "subject_id"])
  end

  defp operator_console_session do
    %{
      session_ref: "extravaganza-operator-console",
      tenant_ref: "tenant://extravaganza/default",
      authority_ref: "authority://extravaganza/operator",
      installation_ref: "installation://extravaganza/default",
      operator_ref: "operator://extravaganza/console",
      trace_ref: "trace://extravaganza/operator-console",
      release_manifest_ref: "release://phase-f/operator-console"
    }
  end

  defp operator_console_sections do
    tenant_ref = "tenant://extravaganza/default"

    %{
      memory: [
        %{tenant_ref: tenant_ref, ref: "memory://extravaganza/session-scope", status: "bounded"}
      ],
      prompts: [
        %{tenant_ref: tenant_ref, ref: "prompt://extravaganza/coding-ops", status: "active"}
      ],
      guards: [
        %{tenant_ref: tenant_ref, ref: "guard-chain://extravaganza/default", status: "active"}
      ],
      replay: [
        %{tenant_ref: tenant_ref, ref: "replay://extravaganza/latest", status: "available"}
      ],
      evals: [
        %{tenant_ref: tenant_ref, ref: "eval-run://extravaganza/latest", status: "passing"}
      ],
      costs: [
        %{tenant_ref: tenant_ref, ref: "cost-dashboard://extravaganza", status: "redacted"}
      ],
      connectors: [
        %{
          tenant_ref: tenant_ref,
          ref: "connector://extravaganza/linear-safe-read",
          status: "admitted"
        }
      ],
      skills: [
        %{tenant_ref: tenant_ref, ref: "skill://pending/phase-g", status: "reserved"}
      ],
      hive: [
        %{tenant_ref: tenant_ref, ref: "hive://pending/phase-h", status: "reserved"}
      ]
    }
  end
end
