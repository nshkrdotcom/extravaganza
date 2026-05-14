defmodule ExtravaganzaWeb.Api.HeadlessController do
  use ExtravaganzaWeb, :controller

  alias Extravaganza.{HeadlessJSON, HeadlessSurface, SymphonyWorkflowImport}

  alias Extravaganza.Presenters.{
    CommandResultPresenter,
    EventPresenter,
    EvidencePresenter,
    LeasePresenter,
    ReviewPresenter,
    RunPresenter,
    RuntimePresenter,
    SourcePresenter,
    StatePresenter,
    SubjectPresenter
  }

  alias ExtravaganzaWeb.ObservabilityUpdates

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

  @spec state(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def state(conn, params) do
    case HeadlessSurface.state_snapshot(params) do
      {:ok, snapshot} ->
        render_success(conn, :state, StatePresenter.present(snapshot, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec status(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def status(conn, params) do
    case HeadlessSurface.runtime_status(params) do
      {:ok, status} ->
        render_success(
          conn,
          :status,
          RuntimePresenter.present_status(status, presenter_opts(conn))
        )

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec logs(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def logs(conn, params) do
    case HeadlessSurface.runtime_logs(params) do
      {:ok, logs} ->
        render_success(conn, :logs, RuntimePresenter.present_logs(logs, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec profile(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def profile(conn, params) do
    case SymphonyWorkflowImport.profile(params) do
      {:ok, profile} -> render_success(conn, :profile, profile)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @spec profile_validate(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def profile_validate(conn, params) do
    case SymphonyWorkflowImport.profile(params) do
      {:ok, %{"validation" => %{"status" => "valid"}} = profile} ->
        render_success(conn, :profile_validate, %{"status" => "valid", "profile" => profile})

      {:ok, %{"validation" => %{"reason" => reason}}} ->
        render_error(conn, reason)

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec profile_reload(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def profile_reload(conn, params) do
    result =
      with {:ok, reload} <- SymphonyWorkflowImport.reload(params) do
        apply_runtime_profile_to_reload(reload)
      end

    case result do
      {:ok, reload} -> render_success(conn, :profile_reload, reload)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @spec subject(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def subject(conn, %{"subject_id" => subject_id} = params) do
    case HeadlessSurface.subject_detail(subject_id, params) do
      {:ok, detail} ->
        render_success(conn, :subject, SubjectPresenter.present(detail, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec issue_subject(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def issue_subject(conn, %{"issue_identifier" => issue_identifier} = params) do
    case HeadlessSurface.subject_by_issue_identifier(issue_identifier, params) do
      {:ok, detail} ->
        render_success(conn, :subject, SubjectPresenter.present(detail, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec run(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def run(conn, %{"run_id" => run_id} = params) do
    case HeadlessSurface.run_detail(run_id, params) do
      {:ok, detail} ->
        render_success(conn, :run, RunPresenter.present(detail, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec refresh(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def refresh(conn, params) do
    case HeadlessSurface.request_refresh(params) do
      {:ok, result} ->
        presented = CommandResultPresenter.present(result, presenter_opts(conn))

        broadcast_command_update(:refresh_requested, presented, %{
          "surface" => "api",
          "command_kind" => "refresh",
          "idempotency_key" => Map.get(params, "idempotency_key")
        })

        render_success(conn, :refresh, presented)

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec control(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def control(conn, %{"subject_id" => subject_id, "action" => action} = params) do
    case HeadlessSurface.request_control(subject_id, action, params) do
      {:ok, result} ->
        presented = CommandResultPresenter.present(result, presenter_opts(conn))

        if accepted_command?(presented) do
          broadcast_command_update(:run_status_change, presented, %{
            "surface" => "api",
            "subject_ref" => subject_id,
            "action" => action,
            "idempotency_key" => Map.get(params, "idempotency_key")
          })
        end

        render_success(conn, :control, presented)

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec read_lease(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def read_lease(conn, %{"subject_id" => subject_id}) do
    case HeadlessSurface.issue_read_lease(subject_id) do
      {:ok, lease} ->
        render_success(conn, :read_lease, LeasePresenter.present(lease, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec stream_attach_lease(Plug.Conn.t(), map()) :: Plug.Conn.t()
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

  @spec source_publication(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def source_publication(conn, %{"subject_id" => subject_id}) do
    case HeadlessSurface.source_publication_preview(subject_id) do
      {:ok, preview} ->
        render_success(
          conn,
          :source_publication,
          SourcePresenter.present_publication_preview(preview, presenter_opts(conn))
        )

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec source_publish(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def source_publish(conn, params) do
    case HeadlessSurface.publish_linear_source(source_publish_attrs(params)) do
      {:ok, result} ->
        presented = SourcePresenter.present_publication_preview(result, presenter_opts(conn))

        ObservabilityUpdates.broadcast_update(:live_provider_receipt, %{
          "surface" => "api",
          "trigger" => "source_sync",
          "subject_ref" => source_publish_subject_ref(params),
          "effect" => source_publish_effect(params),
          "provider" => get_in(presented, ["data", "provider"]),
          "source_publication_ref" =>
            get_in(presented, ["data", "source_publication_receipt_ref"]),
          "status" => get_in(presented, ["data", "status"])
        })

        render_success(conn, :source_publish, presented)

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec reviews(Plug.Conn.t(), map()) :: Plug.Conn.t()
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

  @spec review_decision(Plug.Conn.t(), map()) :: Plug.Conn.t()
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
        presented = CommandResultPresenter.present(result, presenter_opts(conn))

        if accepted_command?(presented) do
          broadcast_command_update(:review_decision, presented, %{
            "surface" => "api",
            "decision_ref" => decision_id,
            "decision" => decision,
            "subject_ref" => Map.get(params, "subject_id")
          })
        end

        render_success(conn, :review, presented)

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec evidence(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def evidence(conn, %{"run_id" => run_id} = params) do
    case HeadlessSurface.evidence_chain(run_id, params) do
      {:ok, evidence} ->
        render_success(conn, :evidence, EvidencePresenter.present(evidence, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec events(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def events(conn, params) do
    case HeadlessSurface.events(params) do
      {:ok, events} ->
        render_success(conn, :events, EventPresenter.present_page(events, presenter_opts(conn)))

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @spec method_not_allowed(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def method_not_allowed(conn, _params), do: render_error(conn, :method_not_allowed)

  @spec not_found(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def not_found(conn, _params), do: render_error(conn, :not_found)

  defp render_success(conn, operation, data) do
    conn
    |> put_status(success_status(operation, data))
    |> json(HeadlessJSON.success(operation, data, presenter_opts(conn)))
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

  defp success_status(operation, data) when operation in [:refresh, :review, :control] do
    if accepted_command?(data), do: :accepted, else: :ok
  end

  defp success_status(_operation, _data), do: :ok

  defp accepted_command?(%{} = data) do
    case get_in(data, ["data", "status"]) || get_in(data, ["data", "workflow_effect_state"]) do
      "accepted" -> true
      "pending_signal" -> true
      _other -> false
    end
  end

  defp apply_runtime_profile_to_reload(
         %{"status" => "reloaded", "profile" => %{"app_kit_runtime_profile" => runtime_profile}} =
           reload
       ) do
    with {:ok, apply_result} <- HeadlessSurface.apply_runtime_profile(runtime_profile) do
      apply_readback = RuntimePresenter.present_profile_apply(apply_result)

      {:ok,
       reload
       |> Map.put("runtime_profile_apply", apply_readback)
       |> Map.put("runtime_profile_ref", apply_readback["profile_ref"])}
    end
  end

  defp apply_runtime_profile_to_reload(reload), do: {:ok, reload}

  defp source_publish_attrs(%{"subject_id" => subject_id} = params),
    do:
      params
      |> Map.delete("subject_id")
      |> Map.put("subject_ref", subject_id)
      |> source_publish_attrs()

  defp source_publish_attrs(params) do
    %{
      "subject_ref" => Map.get(params, "subject_ref", "subject:fixture"),
      "effect" => Map.get(params, "effect", "comment"),
      "message" => Map.get(params, "message", "Headless source publication"),
      "idempotency_key" => Map.get(params, "idempotency_key", "idem:headless-source-publish")
    }
  end

  defp source_publish_subject_ref(%{"subject_id" => subject_id}), do: subject_id
  defp source_publish_subject_ref(params), do: Map.get(params, "subject_ref", "subject:fixture")

  defp source_publish_effect(params), do: Map.get(params, "effect", "comment")

  defp broadcast_command_update(reason, presented, metadata) do
    presented_data = Map.get(presented, "data", %{})

    metadata =
      Map.merge(
        %{
          "command_ref" => Map.get(presented_data, "command_ref"),
          "command_kind" => Map.get(presented_data, "command_kind"),
          "workflow_effect_state" => Map.get(presented_data, "workflow_effect_state"),
          "correlation_id" => Map.get(presented_data, "correlation_id")
        },
        metadata
      )

    ObservabilityUpdates.broadcast_update(reason, metadata)
  end

  defp presenter_opts(conn) do
    [
      correlation_id: conn.assigns[:correlation_id],
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    ]
  end
end
