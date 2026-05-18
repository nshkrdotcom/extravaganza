defmodule ExtravaganzaWeb.Api.HeadlessController do
  use ExtravaganzaWeb, :controller

  alias Extravaganza.{
    HeadlessJSON,
    HeadlessPreflight,
    HeadlessShutdown,
    HeadlessSurface,
    ProductHost,
    SymphonyWorkflowImport
  }

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

  @live_ack_param "ack_headless_guardrails"
  @live_ack_params [@live_ack_param, "ack-headless-guardrails", "guardrails_ack"]
  @live_forbidden_credential_params ~w[
    access_token api_key auth_json authorization authorization_header codex_api_key
    gh_token github_token lease_token linear_api_key openai_api_key provider_payload
    raw_secret raw_token secret target_credentials token token_file
  ]

  @status_by_code %{
    "not_found" => :not_found,
    "projection_unavailable" => :not_found,
    "bad_request" => :bad_request,
    "live_product_path_required" => :bad_request,
    "requires_live_product_path" => :bad_request,
    "invalid_action" => :unprocessable_entity,
    "invalid_workflow_config" => :unprocessable_entity,
    "workflow_front_matter_not_a_map" => :unprocessable_entity,
    "workflow_parse_error" => :unprocessable_entity,
    "missing_workflow_file" => :bad_request,
    "unsupported_tracker_kind" => :unprocessable_entity,
    "incompatible_product_runtime_profile" => :unprocessable_entity,
    "unsupported_runtime_profile_change" => :unprocessable_entity,
    "credential_stdin_empty" => :unauthorized,
    "credential_not_supplied_to_product_command" => :unauthorized,
    "missing_linear_api_token" => :unauthorized,
    "missing_provider_credential" => :unauthorized,
    "action_denied" => :forbidden,
    "unauthorized_lower_read" => :forbidden,
    "provider_denied" => :forbidden,
    "provider_authority_denied" => :forbidden,
    "policy_denied" => :forbidden,
    "provider_failed" => :bad_gateway,
    "provider_error" => :bad_gateway,
    "provider_timeout" => :service_unavailable,
    "archived" => :gone,
    "snapshot_timeout" => :service_unavailable,
    "unavailable" => :service_unavailable,
    "live_surface_dependency_failed" => :service_unavailable,
    "startup_failed" => :service_unavailable,
    "app_not_started" => :service_unavailable,
    "temporal_substrate_unavailable" => :service_unavailable,
    "lower_run_posture_required" => :conflict,
    "active_lower_runs_present" => :conflict,
    "runtime_installation_not_provisioned" => :service_unavailable,
    "method_not_allowed" => :method_not_allowed,
    "operator_ack_required" => :bad_request,
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
        presenter_opts =
          conn
          |> presenter_opts()
          |> Keyword.put(:workflow_reload, SymphonyWorkflowImport.reload_status(params))

        render_success(
          conn,
          :status,
          RuntimePresenter.present_status(status, presenter_opts)
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

  @spec preflight(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def preflight(conn, params) do
    case HeadlessPreflight.run(params) do
      {:ok, report} -> render_success(conn, :preflight, report)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @spec shutdown(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def shutdown(conn, params) do
    case HeadlessShutdown.run(params) do
      {:ok, report} -> render_success(conn, :stop, report)
      {:error, reason} -> render_error(conn, reason)
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
        apply_runtime_profile_to_reload(reload, params)
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
    case HeadlessSurface.publish_source_update(source_publish_attrs(params)) do
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

  @spec live_linear_source(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def live_linear_source(conn, params) do
    live_example(conn, params, "live.linear-source", &ProductHost.live_linear_source_example/1)
  end

  @spec live_linear_current_states(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def live_linear_current_states(conn, params) do
    live_example(
      conn,
      params,
      "live.linear-current-states",
      &ProductHost.live_linear_current_states_example/1
    )
  end

  @spec live_codex_turn(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def live_codex_turn(conn, params) do
    live_example(conn, params, "live.codex-turn", &ProductHost.live_codex_turn_example/1)
  end

  @spec live_linear_publication(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def live_linear_publication(conn, params) do
    live_example(
      conn,
      params,
      "live.linear-publication",
      &ProductHost.live_linear_publication_example/1
    )
  end

  @spec live_linear_graphql_tool(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def live_linear_graphql_tool(conn, params) do
    live_example(
      conn,
      params,
      "live.linear-graphql-tool",
      &ProductHost.live_linear_graphql_tool_example/1
    )
  end

  @spec live_github_evidence(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def live_github_evidence(conn, params) do
    live_example(
      conn,
      params,
      "live.github-evidence",
      &ProductHost.live_github_evidence_example/1
    )
  end

  @spec live_github_pr_cleanup(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def live_github_pr_cleanup(conn, params) do
    live_example(
      conn,
      params,
      "live.github-pr-cleanup",
      &ProductHost.live_github_pr_cleanup_example/1
    )
  end

  @spec live_smoke(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def live_smoke(conn, params) do
    live_example(conn, params, "live.smoke", &ProductHost.live_smoke/1)
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
    envelope = HeadlessJSON.error(:headless_api, reason, presenter_opts(conn))
    code = get_in(envelope, ["error", "code"])

    conn
    |> put_status(Map.get(@status_by_code, code, :internal_server_error))
    |> json(envelope)
  end

  defp render_live_error(conn, operation, params, reason) do
    envelope = HeadlessJSON.error(operation, reason, live_presenter_opts(conn, params))
    code = get_in(envelope, ["error", "code"])

    conn
    |> put_status(Map.get(@status_by_code, code, :internal_server_error))
    |> json(envelope)
  end

  defp live_example(conn, params, operation, callback) when is_function(callback, 1) do
    case live_request_error(params, operation) do
      nil ->
        envelope =
          HeadlessJSON.wrap(
            operation,
            callback.(live_opts(params)),
            fn value -> value end,
            live_presenter_opts(conn, params)
          )

        conn
        |> put_status(envelope_status(envelope))
        |> json(envelope)

      reason ->
        render_live_error(conn, operation, params, reason)
    end
  end

  defp envelope_status(%{"ok" => true}), do: :ok

  defp envelope_status(%{"error" => %{"code" => code}}),
    do: Map.get(@status_by_code, code, :internal_server_error)

  defp live_request_error(params, operation) do
    cond do
      credential_param = raw_credential_param(params) ->
        {:bad_request,
         %{
           "reason" => "raw_provider_credential_param_not_supported",
           "parameter" => credential_param
         }}

      not live_acknowledged?(params) ->
        {:operator_ack_required,
         %{
           operation: operation,
           required_flags: [@live_ack_param],
           legacy_flag_supported?: false,
           reason: "live_api_route"
         }}

      true ->
        nil
    end
  end

  defp raw_credential_param(params) do
    Enum.find(@live_forbidden_credential_params, &Map.has_key?(params, &1))
  end

  defp live_acknowledged?(params) do
    Enum.any?(@live_ack_params, fn key -> truthy?(Map.get(params, key)) end)
  end

  defp live_opts(params) do
    %{}
    |> maybe_put_string_param(params, :connection_id, ["connection_id"])
    |> maybe_put_string_param(params, :credential_ref, ["credential_ref"])
    |> maybe_put_string_param(params, :credential_lease_ref, ["credential_lease_ref"])
    |> maybe_put_string_param(params, :fixture, ["fixture"])
    |> maybe_put_string_param(params, :repo, ["repo"])
    |> maybe_put_string_param(params, :branch, ["branch"])
    |> maybe_put_string_param(params, :pull_number, ["pull_number"])
    |> maybe_put_string_param(params, :ref, ["ref"])
    |> maybe_put_string_param(params, :issue_id, ["issue_id"])
    |> maybe_put_string_param(params, :comment_id, ["comment_id"])
    |> maybe_put_string_param(params, :state_id, ["state_id"])
    |> maybe_put_string_param(params, :state_name, ["state_name"])
    |> maybe_put_string_param(params, :project_slug, ["project_slug"])
    |> maybe_put_string_param(params, :team_id, ["team_id"])
    |> maybe_put_string_param(params, :assignee, ["assignee"])
    |> maybe_put_string_param(params, :message, ["message"])
    |> maybe_put_string_param(params, :closing_comment, ["closing_comment"])
    |> maybe_put_string_param(params, :query, ["query"])
    |> maybe_put_string_param(params, :variables_json, ["variables_json"])
    |> maybe_put_string_param(params, :cursor, ["cursor"])
    |> maybe_put_string_param(params, :limit, ["limit"])
    |> maybe_put_string_param(params, :tenant_id, ["tenant_id"])
    |> maybe_put_string_param(params, :pack_version, ["pack_version"])
    |> maybe_put_string_param(params, :trace_id, ["trace_id"])
    |> maybe_put_list_param(params, :issue_ids, ["issue_ids"])
    |> maybe_put_list_param(params, :source_state_names, [
      "source_state_names",
      "source_states",
      "source_state"
    ])
    |> maybe_put_bool_param(params, :credential_available?, [
      "credential_available",
      "credential_available?"
    ])
    |> maybe_put_bool_param(params, :live_product_path?, [
      "live_product_path",
      "live_product_path?"
    ])
    |> maybe_put_bool_param(params, :allow_create_fallback?, [
      "allow_create_fallback",
      "allow_create_fallback?"
    ])
    |> maybe_put_bool_param(params, :dry_run?, ["dry_run", "dry_run?"])
    |> maybe_put_bool_param(params, :confirm_close?, ["confirm_close", "confirm_close?"])
    |> put_default_live_fixture()
    |> live_product_defaults()
    |> Map.put_new(:credential_available?, false)
  end

  defp put_default_live_fixture(%{live_product_path?: true} = opts), do: opts
  defp put_default_live_fixture(opts), do: Map.put_new(opts, :fixture, "headless_live")

  defp live_product_defaults(%{live_product_path?: true} = opts) do
    unique = System.unique_integer([:positive])

    opts
    |> Map.put_new(:tenant_id, "extravaganza-live-api-#{unique}")
    |> Map.put_new(:pack_version, "1.0.0-live-api.#{unique}")
  end

  defp live_product_defaults(opts), do: opts

  defp maybe_put_string_param(opts, params, key, param_keys) do
    case string_param(params, param_keys) do
      nil -> opts
      value -> Map.put(opts, key, value)
    end
  end

  defp maybe_put_bool_param(opts, params, key, param_keys) do
    case first_param(params, param_keys) do
      {:ok, value} -> Map.put(opts, key, truthy?(value))
      :error -> opts
    end
  end

  defp maybe_put_list_param(opts, params, key, param_keys) do
    case first_param(params, param_keys) do
      {:ok, value} ->
        values = list_param(value)
        if values == [], do: opts, else: Map.put(opts, key, values)

      :error ->
        opts
    end
  end

  defp string_param(params, param_keys) do
    case first_param(params, param_keys) do
      {:ok, value} -> string_value(value)
      :error -> nil
    end
  end

  defp first_param(params, param_keys) do
    Enum.find_value(param_keys, :error, fn key ->
      if Map.has_key?(params, key), do: {:ok, Map.get(params, key)}
    end)
  end

  defp string_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp string_value(value) when is_integer(value), do: Integer.to_string(value)
  defp string_value(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp string_value(_value), do: nil

  defp list_param(values) when is_list(values) do
    values
    |> Enum.map(&string_value/1)
    |> Enum.reject(&is_nil/1)
  end

  defp list_param(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp list_param(value) do
    case string_value(value) do
      nil -> []
      value -> [value]
    end
  end

  defp truthy?(value), do: value in [true, "true", 1, "1"]

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
           reload,
         params
       ) do
    with {:ok, apply_result} <- HeadlessSurface.apply_runtime_profile(runtime_profile) do
      apply_readback = RuntimePresenter.present_profile_apply(apply_result)

      reload =
        reload
        |> Map.put("runtime_profile_apply", apply_readback)
        |> Map.put("runtime_profile_ref", apply_readback["profile_ref"])

      with :ok <- SymphonyWorkflowImport.record_runtime_profile_apply(reload, params) do
        {:ok, reload}
      end
    end
  end

  defp apply_runtime_profile_to_reload(reload, _params), do: {:ok, reload}

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

  defp live_presenter_opts(conn, params) do
    case string_param(params, ["trace_id"]) do
      nil -> presenter_opts(conn)
      trace_id -> Keyword.put(presenter_opts(conn), :trace_id, trace_id)
    end
  end
end
