defmodule Extravaganza.HeadlessCLI.Dispatch do
  @moduledoc false

  alias Extravaganza.Presenters.{
    CommandResultPresenter,
    EventPresenter,
    EvidencePresenter,
    ReviewPresenter,
    RunPresenter,
    RuntimePresenter,
    SourcePresenter,
    StatePresenter,
    SubjectPresenter
  }

  alias Extravaganza.{
    HeadlessFixtureBackend,
    HeadlessJSON,
    HeadlessPreflight,
    HeadlessShutdown,
    HeadlessSurface,
    ProductHost,
    SymphonyWorkflowImport
  }

  @spec run(atom(), map()) :: map()
  def run(operation, opts) when is_atom(operation) and is_map(opts), do: dispatch(operation, opts)

  defp dispatch(:state, opts),
    do:
      HeadlessJSON.wrap(
        :state,
        HeadlessSurface.state_snapshot(%{}, surface_opts(opts)),
        &StatePresenter.present/1,
        opts
      )

  defp dispatch(:queue, opts) do
    case HeadlessSurface.operator_queue(%{}, surface_opts(opts)) do
      {:ok, queue} -> HeadlessJSON.success(:queue, StatePresenter.present_queue(queue), opts)
      {:error, reason} -> HeadlessJSON.error(:queue, reason, opts)
    end
  end

  defp dispatch(:subject, opts) do
    subject_id = positional(opts, 0) || Map.get(opts, :subject_id) || "subject:fixture"

    HeadlessJSON.wrap(
      :subject,
      HeadlessSurface.subject_detail(subject_id, %{}, surface_opts(opts)),
      &SubjectPresenter.present/1,
      opts
    )
  end

  defp dispatch(:run, opts) do
    run_id = positional(opts, 0) || Map.get(opts, :run_id) || "run:fixture"

    HeadlessJSON.wrap(
      :run,
      HeadlessSurface.run_detail(run_id, %{}, surface_opts(opts)),
      &RunPresenter.present/1,
      opts
    )
  end

  defp dispatch(:start, opts) do
    if Map.has_key?(opts, :fixture) do
      :run
      |> dispatch(Map.put(opts, :operation_override, :start))
      |> Map.put("operation", "start")
    else
      HeadlessJSON.wrap(
        :start,
        ProductHost.start_run(default_linear_subject(opts), product_opts(opts)),
        &present_start_result/1,
        opts
      )
    end
  end

  defp dispatch(:refresh, opts) do
    attrs = %{"idempotency_key" => Map.get(opts, :idempotency_key) || "idem:headless-refresh"}

    HeadlessJSON.wrap(
      :refresh,
      HeadlessSurface.request_refresh(attrs, surface_opts(opts)),
      &CommandResultPresenter.present/1,
      opts
    )
  end

  defp dispatch(:control, opts) do
    subject_id = positional(opts, 0) || Map.get(opts, :subject_id) || "subject:fixture"
    action = Map.get(opts, :action) || positional(opts, 1) || "retry"
    attrs = %{"idempotency_key" => Map.get(opts, :idempotency_key) || "idem:headless-control"}

    HeadlessJSON.wrap(
      :control,
      HeadlessSurface.request_control(subject_id, action, attrs, surface_opts(opts)),
      &CommandResultPresenter.present/1,
      opts
    )
  end

  defp dispatch(:reviews, opts),
    do:
      HeadlessJSON.wrap(
        :reviews,
        HeadlessSurface.list_reviews(%{}, surface_opts(opts)),
        &ReviewPresenter.present_page/1,
        opts
      )

  defp dispatch(:review, opts) do
    decision_id = positional(opts, 0) || Map.get(opts, :decision_id) || "decision:fixture"
    decision = Map.get(opts, :decision) || "accept"

    identity = %{
      id: decision_id,
      decision_kind: "operator_review",
      subject_id: Map.get(opts, :subject_id) || "subject:fixture",
      subject_kind: "linear_issue"
    }

    attrs = %{
      "decision" => decision,
      "reason" => Map.get(opts, :reason) || "headless fixture decision"
    }

    HeadlessJSON.wrap(
      :review,
      HeadlessSurface.record_review_decision(identity, attrs, surface_opts(opts)),
      &CommandResultPresenter.present/1,
      opts
    )
  end

  defp dispatch(:source_preview, opts) do
    subject_id = positional(opts, 0) || Map.get(opts, :subject_id) || "subject:fixture"

    HeadlessJSON.wrap(
      :source_preview,
      HeadlessSurface.source_publication_preview(subject_id, surface_opts(opts)),
      &SourcePresenter.present_publication_preview/1,
      opts
    )
  end

  defp dispatch(:source_sync, opts) do
    HeadlessJSON.wrap(
      :source_sync,
      ProductHost.sync_issue_tracker_source(
        %{issues: [default_linear_issue(opts)]},
        product_opts(opts)
      ),
      fn value -> value end,
      opts
    )
  end

  defp dispatch(:source_publish, opts) do
    subject_ref = positional(opts, 0) || Map.get(opts, :subject_id) || "subject:fixture"

    attrs = %{
      subject_ref: subject_ref,
      effect: Map.get(opts, :effect) || "comment",
      idempotency_key: Map.get(opts, :idempotency_key) || "idem:headless-source-publish",
      message: Map.get(opts, :message) || "Headless source publication"
    }

    HeadlessJSON.wrap(
      :source_publish,
      HeadlessSurface.publish_source_update(attrs, surface_opts(opts)),
      &SourcePresenter.present_publication_preview/1,
      opts
    )
  end

  defp dispatch(:profile, opts) do
    HeadlessJSON.wrap(
      :profile,
      SymphonyWorkflowImport.profile(import_opts(opts)),
      fn value -> value end,
      opts
    )
  end

  defp dispatch(:profile_validate, opts) do
    with {:ok, profile} <- SymphonyWorkflowImport.profile(import_opts(opts)) do
      case profile["validation"] do
        %{"status" => "valid"} ->
          HeadlessJSON.success(
            :profile_validate,
            %{"status" => "valid", "profile" => profile},
            opts
          )

        %{"reason" => %{"code" => code, "value" => value}} ->
          HeadlessJSON.error(:profile_validate, {code, value}, opts)

        %{"reason" => reason} ->
          HeadlessJSON.error(:profile_validate, reason, opts)
      end
    end
  end

  defp dispatch(:profile_reload, opts) do
    result =
      with {:ok, reload} <- SymphonyWorkflowImport.reload(import_opts(opts)) do
        apply_runtime_profile_to_reload(reload, opts)
      end

    HeadlessJSON.wrap(
      :profile_reload,
      result,
      fn value -> value end,
      opts
    )
  end

  defp dispatch(:status, opts) do
    workflow_reload = SymphonyWorkflowImport.reload_status(import_opts(opts))

    HeadlessJSON.wrap(
      :status,
      HeadlessSurface.runtime_status(runtime_request(opts), surface_opts(opts)),
      fn status -> RuntimePresenter.present_status(status, workflow_reload: workflow_reload) end,
      opts
    )
  end

  defp dispatch(:logs, opts) do
    HeadlessJSON.wrap(
      :logs,
      HeadlessSurface.runtime_logs(runtime_request(opts), surface_opts(opts)),
      &RuntimePresenter.present_logs/1,
      opts
    )
  end

  defp dispatch(:preflight, opts) do
    HeadlessJSON.wrap(
      :preflight,
      HeadlessPreflight.run(preflight_opts(opts)),
      fn value -> value end,
      opts
    )
  end

  defp dispatch(:stop, opts) do
    HeadlessJSON.wrap(
      :stop,
      HeadlessShutdown.run(shutdown_opts(opts)),
      fn value -> value end,
      opts
    )
  end

  defp dispatch(:live_linear_source, opts) do
    dispatch_live("live.linear-source", &ProductHost.live_linear_source_example/1, opts)
  end

  defp dispatch(:live_linear_current_states, opts) do
    dispatch_live(
      "live.linear-current-states",
      &ProductHost.live_linear_current_states_example/1,
      opts
    )
  end

  defp dispatch(:live_codex_turn, opts) do
    dispatch_live("live.codex-turn", &ProductHost.live_codex_turn_example/1, opts)
  end

  defp dispatch(:live_linear_publication, opts) do
    dispatch_live("live.linear-publication", &ProductHost.live_linear_publication_example/1, opts)
  end

  defp dispatch(:live_linear_graphql_tool, opts) do
    dispatch_live(
      "live.linear-graphql-tool",
      &ProductHost.live_linear_graphql_tool_example/1,
      opts
    )
  end

  defp dispatch(:live_github_evidence, opts) do
    dispatch_live("live.github-evidence", &ProductHost.live_github_evidence_example/1, opts)
  end

  defp dispatch(:live_github_pr_cleanup, opts) do
    dispatch_live(
      "live.github-pr-cleanup",
      &ProductHost.live_github_pr_cleanup_example/1,
      opts
    )
  end

  defp dispatch(:live_smoke, opts) do
    dispatch_live("live.smoke", &ProductHost.live_smoke/1, opts)
  end

  defp dispatch(:evidence, opts) do
    run_id = positional(opts, 0) || Map.get(opts, :run_id) || "run:fixture"

    HeadlessJSON.wrap(
      :evidence,
      HeadlessSurface.evidence_chain(run_id, %{}, surface_opts(opts)),
      &EvidencePresenter.present/1,
      opts
    )
  end

  defp dispatch(:events, opts) do
    run_id = Map.get(opts, :run_id) || positional(opts, 0) || "run:fixture"

    HeadlessJSON.wrap(
      :events,
      HeadlessSurface.events(%{"run_id" => run_id}, surface_opts(opts)),
      &EventPresenter.present_page/1,
      opts
    )
  end

  defp dispatch(:smoke, %{deterministic?: true, same_run?: true} = opts) do
    HeadlessJSON.wrap(:smoke, ProductHost.same_run_smoke(opts), fn value -> value end, opts)
  end

  defp dispatch(:smoke, opts) do
    results = %{
      "state" => dispatch(:state, opts),
      "run" => dispatch(:run, opts),
      "evidence" => dispatch(:evidence, opts),
      "events" => dispatch(:events, opts),
      "refresh" => dispatch(:refresh, opts)
    }

    if Enum.all?(results, fn {_key, value} -> value["ok"] == true end) do
      HeadlessJSON.success(:smoke, results, opts)
    else
      HeadlessJSON.error(:smoke, :unavailable, opts)
    end
  end

  defp dispatch_live(operation, callback, opts) when is_function(callback, 1) do
    case live_opts(opts) do
      {:ok, live_opts} ->
        HeadlessJSON.wrap(operation, callback.(live_opts), fn value -> value end, opts)

      {:error, reason} ->
        HeadlessJSON.error(operation, reason, opts)
    end
  end

  defp positional(opts, index), do: opts |> Map.get(:positionals, []) |> Enum.at(index)

  defp product_opts(opts) do
    unique = unique_suffix()

    opts
    |> Map.take([:tenant_id, :pack_version, :profile_cache_path])
    |> Map.put_new(:tenant_id, "extravaganza-headless-#{unique}")
    |> Map.put_new(:pack_version, "1.0.0-headless.#{unique}")
    |> maybe_put_fixture_backend_stack(opts)
    |> Enum.to_list()
  end

  defp surface_opts(opts) do
    opts
    |> Map.take([:tenant_id, :pack_version])
    |> maybe_put_fixture_backend_stack(opts)
    |> Enum.to_list()
  end

  defp maybe_put_fixture_backend_stack(selected, %{fixture: _fixture}) do
    Map.put_new(selected, :backend_stack, fixture_backend_stack())
  end

  defp maybe_put_fixture_backend_stack(selected, _opts), do: selected

  defp fixture_backend_stack do
    AppKit.BackendStack.new!(%{
      headless_backend: HeadlessFixtureBackend,
      runtime_backend: HeadlessFixtureBackend,
      source_backend: HeadlessFixtureBackend
    })
  end

  defp live_opts(opts) do
    with {:ok, stdin_credential} <- stdin_credential(opts) do
      live_opts =
        opts
        |> Map.take([
          :api_key_stdin?,
          :credential_available?,
          :connection_id,
          :credential_ref,
          :credential_lease_ref,
          :fixture,
          :live_product_path?,
          :repo,
          :branch,
          :pull_number,
          :ref,
          :issue_id,
          :issue_ids,
          :comment_id,
          :state_id,
          :state_name,
          :source_state_names,
          :project_slug,
          :team_id,
          :assignee,
          :message,
          :closing_comment,
          :query,
          :variables_json,
          :allow_create_fallback?,
          :dry_run?,
          :cursor,
          :limit,
          :tenant_id,
          :pack_version,
          :trace_id,
          :confirm_close?
        ])
        |> Map.merge(stdin_credential)
        |> live_product_defaults()
        |> Map.put_new(:credential_available?, false)

      {:ok, live_opts}
    end
  end

  defp live_product_defaults(%{live_product_path?: true} = opts) do
    unique = unique_suffix()

    opts
    |> Map.put_new(:tenant_id, "extravaganza-live-#{unique}")
    |> Map.put_new(:pack_version, "1.0.0-live.#{unique}")
  end

  defp live_product_defaults(opts), do: opts

  defp stdin_credential(%{api_key_stdin?: true}) do
    case IO.read(:stdio, :eof) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" ->
            {:error, :credential_stdin_empty}

          trimmed ->
            {:ok,
             %{
               credential_available?: true,
               credential_source: "stdin",
               credential_length: byte_size(trimmed),
               api_key: trimmed
             }}
        end

      _other ->
        {:error, :credential_stdin_empty}
    end
  end

  defp stdin_credential(_opts), do: {:ok, %{}}

  defp import_opts(opts) do
    opts
    |> Map.take([:workflow_path, :cwd, :env, :profile_cache_path])
    |> Enum.to_list()
  end

  defp apply_runtime_profile_to_reload(
         %{"status" => "reloaded", "profile" => %{"app_kit_runtime_profile" => runtime_profile}} =
           reload,
         opts
       ) do
    with {:ok, apply_result} <-
           HeadlessSurface.apply_runtime_profile(runtime_profile, surface_opts(opts)) do
      apply_readback = RuntimePresenter.present_profile_apply(apply_result)

      reload =
        reload
        |> Map.put("runtime_profile_apply", apply_readback)
        |> Map.put("runtime_profile_ref", apply_readback["profile_ref"])

      with :ok <- SymphonyWorkflowImport.record_runtime_profile_apply(reload, import_opts(opts)) do
        {:ok, reload}
      end
    end
  end

  defp apply_runtime_profile_to_reload(reload, _opts), do: {:ok, reload}

  defp runtime_request(opts) do
    opts
    |> Map.take([:cursor, :limit, :logs_root, :trace_id])
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp preflight_opts(opts) do
    opts
    |> Map.take([
      :skip_app_start?,
      :temporal_status,
      :source_binding_refs,
      :credential_refs,
      :credential_ref
    ])
    |> Map.put(:backend_opts, surface_opts(opts))
  end

  defp shutdown_opts(opts) do
    Map.take(opts, [
      :active_lower_run_refs,
      :confirm_no_active_lower_runs?,
      :reason,
      :trace_id
    ])
  end

  defp default_linear_subject(opts) do
    issue_id = Map.get(opts, :issue_id) || "HEADLESS-#{unique_suffix()}"
    title = Map.get(opts, :title) || "Headless deterministic start #{issue_id}"
    description = Map.get(opts, :description) || "Admitted by the headless product command path."

    %{
      external_ref: "linear:#{issue_id}",
      title: title,
      description: description,
      source_kind: "linear",
      payload: %{
        "issue_id" => issue_id,
        "identifier" => issue_id,
        "title" => title,
        "description" => description,
        "state" => "Todo"
      },
      normalized_payload: %{
        "issue_id" => issue_id,
        "identifier" => issue_id,
        "title" => title,
        "description" => description,
        "state" => "Todo",
        "labels" => ["headless", "deterministic"]
      }
    }
  end

  defp default_linear_issue(opts) do
    issue_id = Map.get(opts, :issue_id) || "HEADLESS-#{unique_suffix()}"
    title = Map.get(opts, :title) || "Headless deterministic source #{issue_id}"
    description = Map.get(opts, :description) || "Admitted by the headless source command path."

    %{
      id: issue_id,
      identifier: issue_id,
      title: title,
      description: description,
      state: %{name: "Todo", type: "unstarted"},
      labels: ["headless", "deterministic"],
      url: "https://linear.app/example/issue/#{issue_id}",
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp present_start_result(result) do
    data = HeadlessJSON.sanitize(result)
    payload = Map.get(data, "payload", %{})
    run_ref = Map.get(payload, "run_ref", %{})
    subject_ref = Map.get(run_ref, "subject_ref", %{})
    metadata = Map.get(run_ref, "metadata", %{})

    %{
      "surface" => Map.get(data, "surface"),
      "state" => Map.get(data, "state"),
      "subject_ref" => ref_id(subject_ref) || Map.get(payload, "work_object_id"),
      "run_ref" => run_ref_id(run_ref),
      "workflow_ref" => Map.get(payload, "workflow_start_ref"),
      "workflow_dispatch_state" => Map.get(payload, "workflow_dispatch_state"),
      "runtime_profile_ref" => get_in(payload, ["run_request_metadata", "runtime_profile_ref"]),
      "lower_runtime_kind" => get_in(payload, ["run_request_metadata", "lower_runtime_kind"]),
      "idempotency_key" => Map.get(metadata, "idempotency_key"),
      "review_required" => Map.get(payload, "review_required"),
      "review_unit_id" => Map.get(payload, "review_unit_id")
    }
  end

  defp ref_id(%{"id" => id}) when is_binary(id), do: id
  defp ref_id(_value), do: nil

  defp run_ref_id(%{"id" => id}) when is_binary(id), do: id
  defp run_ref_id(%{"run_id" => run_id}) when is_binary(run_id), do: run_id
  defp run_ref_id(_value), do: nil

  defp unique_suffix do
    "#{System.system_time(:microsecond)}-#{System.unique_integer([:positive])}"
  end
end
