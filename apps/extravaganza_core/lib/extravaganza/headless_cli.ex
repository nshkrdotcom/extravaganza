defmodule Extravaganza.HeadlessCLI do
  @moduledoc """
  Product-owned command dispatcher for local headless examples and Mix tasks.
  """

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
    HeadlessSurface,
    ProductHost,
    SymphonyWorkflowImport
  }

  @operations [
    :state,
    :queue,
    :subject,
    :run,
    :start,
    :refresh,
    :control,
    :reviews,
    :review,
    :source_preview,
    :source_sync,
    :source_publish,
    :profile,
    :profile_reload,
    :profile_validate,
    :status,
    :logs,
    :live_linear_source,
    :live_linear_current_states,
    :live_codex_turn,
    :live_linear_publication,
    :live_linear_graphql_tool,
    :live_github_evidence,
    :live_github_pr_cleanup,
    :live_smoke,
    :evidence,
    :events,
    :smoke
  ]

  @live_operations [
    :live_linear_source,
    :live_linear_current_states,
    :live_codex_turn,
    :live_linear_publication,
    :live_linear_graphql_tool,
    :live_github_evidence,
    :live_github_pr_cleanup,
    :live_smoke
  ]

  @mutating_operations [
    :start,
    :refresh,
    :control,
    :review,
    :source_sync,
    :source_publish,
    :profile_reload
  ]

  @guardrails_ack_flag "--ack-headless-guardrails"
  @legacy_guardrails_ack_flag "--i-understand-that-this-will-be-running-without-the-usual-guardrails"
  @guardrails_ack_flags [@guardrails_ack_flag, @legacy_guardrails_ack_flag]

  @operation_envelope_names %{
    live_linear_source: "live.linear-source",
    live_linear_current_states: "live.linear-current-states",
    live_codex_turn: "live.codex-turn",
    live_linear_publication: "live.linear-publication",
    live_linear_graphql_tool: "live.linear-graphql-tool",
    live_github_evidence: "live.github-evidence",
    live_github_pr_cleanup: "live.github-pr-cleanup",
    live_smoke: "live.smoke"
  }

  @spec operations() :: [atom()]
  def operations, do: @operations

  @spec guardrails_ack_flags() :: [String.t()]
  def guardrails_ack_flags, do: @guardrails_ack_flags

  @spec guardrails_acknowledgement_error(atom(), [String.t()]) ::
          nil | {:operator_ack_required, map()}
  def guardrails_acknowledgement_error(operation, argv)
      when is_atom(operation) and is_list(argv) do
    if operation in @operations do
      argv
      |> parse()
      |> maybe_default_live_fixture(operation)
      |> guardrails_acknowledgement_error_from_opts(operation)
    end
  end

  @spec run(atom(), [String.t()]) :: :ok
  def run(operation, argv) when operation in @operations and is_list(argv) do
    opts =
      argv
      |> parse()
      |> maybe_default_live_fixture(operation)

    maybe_install_fixture_backend(opts)

    operation
    |> guarded_dispatch(opts)
    |> print_envelope(operation, opts)
  end

  defp guarded_dispatch(operation, opts) do
    case guardrails_acknowledgement_error_from_opts(opts, operation) do
      nil ->
        dispatch(operation, opts)

      reason ->
        HeadlessJSON.error(operation_envelope_name(operation), reason, opts)
    end
  end

  defp dispatch(:state, opts),
    do:
      HeadlessJSON.wrap(
        :state,
        HeadlessSurface.state_snapshot(%{}, []),
        &StatePresenter.present/1,
        opts
      )

  defp dispatch(:queue, opts) do
    case HeadlessSurface.operator_queue(%{}, []) do
      {:ok, queue} -> HeadlessJSON.success(:queue, StatePresenter.present_queue(queue), opts)
      {:error, reason} -> HeadlessJSON.error(:queue, reason, opts)
    end
  end

  defp dispatch(:subject, opts) do
    subject_id = positional(opts, 0) || Map.get(opts, :subject_id) || "subject:fixture"

    HeadlessJSON.wrap(
      :subject,
      HeadlessSurface.subject_detail(subject_id, %{}, []),
      &SubjectPresenter.present/1,
      opts
    )
  end

  defp dispatch(:run, opts) do
    run_id = positional(opts, 0) || Map.get(opts, :run_id) || "run:fixture"

    HeadlessJSON.wrap(
      :run,
      HeadlessSurface.run_detail(run_id, %{}, []),
      &RunPresenter.present/1,
      opts
    )
  end

  defp dispatch(:start, opts) do
    if Map.has_key?(opts, :fixture) do
      dispatch(:run, Map.put(opts, :operation_override, :start))
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
      HeadlessSurface.request_refresh(attrs, []),
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
      HeadlessSurface.request_control(subject_id, action, attrs, []),
      &CommandResultPresenter.present/1,
      opts
    )
  end

  defp dispatch(:reviews, opts),
    do:
      HeadlessJSON.wrap(
        :reviews,
        HeadlessSurface.list_reviews(%{}, []),
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
      HeadlessSurface.record_review_decision(identity, attrs, []),
      &CommandResultPresenter.present/1,
      opts
    )
  end

  defp dispatch(:source_preview, opts) do
    subject_id = positional(opts, 0) || Map.get(opts, :subject_id) || "subject:fixture"

    HeadlessJSON.wrap(
      :source_preview,
      HeadlessSurface.source_publication_preview(subject_id, []),
      &SourcePresenter.present_publication_preview/1,
      opts
    )
  end

  defp dispatch(:source_sync, opts) do
    HeadlessJSON.wrap(
      :source_sync,
      ProductHost.sync_linear_source(%{issues: [default_linear_issue(opts)]}, product_opts(opts)),
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
      HeadlessSurface.publish_linear_source(attrs, surface_opts(opts)),
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
        apply_runtime_profile_to_reload(reload, surface_opts(opts))
      end

    HeadlessJSON.wrap(
      :profile_reload,
      result,
      fn value -> value end,
      opts
    )
  end

  defp dispatch(:status, opts) do
    HeadlessJSON.wrap(
      :status,
      HeadlessSurface.runtime_status(runtime_request(opts), surface_opts(opts)),
      &RuntimePresenter.present_status/1,
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
      HeadlessSurface.evidence_chain(run_id, %{}, []),
      &EvidencePresenter.present/1,
      opts
    )
  end

  defp dispatch(:events, opts) do
    run_id = Map.get(opts, :run_id) || positional(opts, 0) || "run:fixture"

    HeadlessJSON.wrap(
      :events,
      HeadlessSurface.events(%{"run_id" => run_id}, []),
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

  defp print_envelope(envelope, _operation, opts) do
    envelope =
      case Map.get(opts, :operation_override) do
        nil -> envelope
        override -> %{envelope | "operation" => Atom.to_string(override)}
      end

    IO.puts(Jason.encode!(envelope, pretty: Map.get(opts, :pretty?, true)))
    :ok
  end

  defp parse(argv), do: parse(argv, %{positionals: []})

  defp parse([], opts), do: opts
  defp parse(["--json" | rest], opts), do: parse(rest, opts)
  defp parse(["--pretty" | rest], opts), do: parse(rest, Map.put(opts, :pretty?, true))

  defp parse(["--fixture", fixture | rest], opts),
    do: parse(rest, Map.put(opts, :fixture, fixture))

  defp parse(["--trace-id", trace_id | rest], opts),
    do: parse(rest, Map.put(opts, :trace_id, trace_id))

  defp parse(["--tenant-id", tenant_id | rest], opts),
    do: parse(rest, Map.put(opts, :tenant_id, tenant_id))

  defp parse(["--pack-version", pack_version | rest], opts),
    do: parse(rest, Map.put(opts, :pack_version, pack_version))

  defp parse(["--workflow", workflow_path | rest], opts),
    do: parse(rest, Map.put(opts, :workflow_path, workflow_path))

  defp parse(["--workflow-path", workflow_path | rest], opts),
    do: parse(rest, Map.put(opts, :workflow_path, workflow_path))

  defp parse(["--cwd", cwd | rest], opts), do: parse(rest, Map.put(opts, :cwd, cwd))

  defp parse(["--logs-root", logs_root | rest], opts),
    do: parse(rest, Map.put(opts, :logs_root, Path.expand(logs_root)))

  defp parse(["--profile-cache", profile_cache_path | rest], opts),
    do: parse(rest, Map.put(opts, :profile_cache_path, profile_cache_path))

  defp parse(["--env", assignment | rest], opts) do
    parsed = parse_env_assignment(assignment)
    parse(rest, Map.update(opts, :env, parsed, &Map.merge(&1, parsed)))
  end

  defp parse(["--run", run_id | rest], opts), do: parse(rest, Map.put(opts, :run_id, run_id))
  defp parse(["--run-id", run_id | rest], opts), do: parse(rest, Map.put(opts, :run_id, run_id))

  defp parse(["--subject", subject_id | rest], opts),
    do: parse(rest, Map.put(opts, :subject_id, subject_id))

  defp parse(["--subject-id", subject_id | rest], opts),
    do: parse(rest, Map.put(opts, :subject_id, subject_id))

  defp parse(["--issue-id", issue_id | rest], opts),
    do: parse(rest, Map.put(opts, :issue_id, issue_id))

  defp parse(["--issue-ids", issue_ids | rest], opts),
    do:
      parse(
        rest,
        Map.update(opts, :issue_ids, split_csv(issue_ids), &(split_csv(issue_ids) ++ &1))
      )

  defp parse(["--comment-id", comment_id | rest], opts),
    do: parse(rest, Map.put(opts, :comment_id, comment_id))

  defp parse(["--state-id", state_id | rest], opts),
    do: parse(rest, Map.put(opts, :state_id, state_id))

  defp parse(["--state-name", state_name | rest], opts),
    do: parse(rest, Map.put(opts, :state_name, state_name))

  defp parse(["--source-state", state_name | rest], opts),
    do:
      parse(
        rest,
        Map.update(opts, :source_state_names, [state_name], &(&1 ++ [state_name]))
      )

  defp parse(["--source-states", state_names | rest], opts),
    do:
      parse(
        rest,
        Map.update(
          opts,
          :source_state_names,
          split_csv(state_names),
          &(split_csv(state_names) ++ &1)
        )
      )

  defp parse(["--project-slug", project_slug | rest], opts),
    do: parse(rest, Map.put(opts, :project_slug, project_slug))

  defp parse(["--team-id", team_id | rest], opts),
    do: parse(rest, Map.put(opts, :team_id, team_id))

  defp parse(["--assignee", assignee | rest], opts),
    do: parse(rest, Map.put(opts, :assignee, assignee))

  defp parse(["--allow-create-fallback" | rest], opts),
    do: parse(rest, Map.put(opts, :allow_create_fallback?, true))

  defp parse(["--no-create-fallback" | rest], opts),
    do: parse(rest, Map.put(opts, :allow_create_fallback?, false))

  defp parse(["--dry-run" | rest], opts), do: parse(rest, Map.put(opts, :dry_run?, true))

  defp parse(["--query", query | rest], opts), do: parse(rest, Map.put(opts, :query, query))

  defp parse(["--variables-json", variables_json | rest], opts),
    do: parse(rest, Map.put(opts, :variables_json, variables_json))

  defp parse(["--repo", repo | rest], opts), do: parse(rest, Map.put(opts, :repo, repo))

  defp parse(["--branch", branch | rest], opts), do: parse(rest, Map.put(opts, :branch, branch))

  defp parse(["--pull-number", pull_number | rest], opts),
    do: parse(rest, Map.put(opts, :pull_number, pull_number))

  defp parse(["--ref", ref | rest], opts), do: parse(rest, Map.put(opts, :ref, ref))

  defp parse(["--title", title | rest], opts), do: parse(rest, Map.put(opts, :title, title))

  defp parse(["--description", description | rest], opts),
    do: parse(rest, Map.put(opts, :description, description))

  defp parse(["--message", message | rest], opts),
    do: parse(rest, Map.put(opts, :message, message))

  defp parse(["--closing-comment", comment | rest], opts),
    do: parse(rest, Map.put(opts, :closing_comment, comment))

  defp parse(["--effect", effect | rest], opts), do: parse(rest, Map.put(opts, :effect, effect))

  defp parse(["--idempotency-key", idempotency_key | rest], opts),
    do: parse(rest, Map.put(opts, :idempotency_key, idempotency_key))

  defp parse(["--cursor", cursor | rest], opts), do: parse(rest, Map.put(opts, :cursor, cursor))

  defp parse(["--limit", limit | rest], opts), do: parse(rest, Map.put(opts, :limit, limit))

  defp parse(["--action", action | rest], opts), do: parse(rest, Map.put(opts, :action, action))

  defp parse(["--decision", decision | rest], opts),
    do: parse(rest, Map.put(opts, :decision, decision))

  defp parse(["--reason", reason | rest], opts), do: parse(rest, Map.put(opts, :reason, reason))

  defp parse(["--deterministic" | rest], opts),
    do: parse(rest, Map.put(opts, :deterministic?, true))

  defp parse(["--same-run" | rest], opts), do: parse(rest, Map.put(opts, :same_run?, true))

  defp parse(["--live-product-path" | rest], opts),
    do: parse(rest, Map.put(opts, :live_product_path?, true))

  defp parse([@guardrails_ack_flag | rest], opts),
    do: parse(rest, Map.put(opts, :guardrails_ack?, true))

  defp parse([@legacy_guardrails_ack_flag | rest], opts),
    do: parse(rest, Map.put(opts, :guardrails_ack?, true))

  defp parse(["--api-key-stdin" | rest], opts),
    do: parse(rest, Map.put(opts, :api_key_stdin?, true))

  defp parse(["--connection-id", connection_id | rest], opts),
    do: parse(rest, Map.put(opts, :connection_id, connection_id))

  defp parse(["--credential-ref", credential_ref | rest], opts),
    do: parse(rest, Map.put(opts, :credential_ref, credential_ref))

  defp parse(["--credential-lease-ref", credential_lease_ref | rest], opts),
    do: parse(rest, Map.put(opts, :credential_lease_ref, credential_lease_ref))

  defp parse(["--credential-available" | rest], opts),
    do: parse(rest, Map.put(opts, :credential_available?, true))

  defp parse(["--confirm-close" | rest], opts),
    do: parse(rest, Map.put(opts, :confirm_close?, true))

  defp parse([value | rest], opts) do
    parse(rest, Map.update!(opts, :positionals, &(&1 ++ [value])))
  end

  defp maybe_install_fixture_backend(%{fixture: _fixture}) do
    Application.put_env(:app_kit_core, :headless_backend, HeadlessFixtureBackend)

    unless Application.get_env(:app_kit_core, :source_backend) do
      Application.put_env(:app_kit_core, :source_backend, HeadlessFixtureBackend)
    end

    Application.put_env(:extravaganza_core, :headless_fixture_context?, true)
  end

  defp maybe_install_fixture_backend(_opts), do: :ok

  defp maybe_default_live_fixture(%{live_product_path?: true} = opts, _operation), do: opts

  defp maybe_default_live_fixture(%{fixture: _fixture} = opts, _operation), do: opts

  defp maybe_default_live_fixture(opts, operation) when operation in @live_operations do
    Map.put(opts, :fixture, "headless_live")
  end

  defp maybe_default_live_fixture(opts, _operation), do: opts

  defp positional(opts, index), do: opts |> Map.get(:positionals, []) |> Enum.at(index)

  defp guardrails_acknowledgement_error_from_opts(opts, operation) do
    if guardrails_ack_required?(operation, opts) and not truthy?(Map.get(opts, :guardrails_ack?)) do
      {:operator_ack_required,
       %{
         operation: operation_envelope_name(operation),
         required_flags: @guardrails_ack_flags,
         legacy_flag_supported?: true,
         reason: guardrails_ack_reason(operation, opts)
       }}
    else
      nil
    end
  end

  defp guardrails_ack_required?(operation, opts) do
    cond do
      deterministic_fixture_without_live_path?(opts) ->
        false

      operation in @live_operations and truthy?(Map.get(opts, :live_product_path?)) ->
        true

      operation in @mutating_operations ->
        true

      true ->
        false
    end
  end

  defp deterministic_fixture_without_live_path?(opts),
    do: Map.has_key?(opts, :fixture) and not truthy?(Map.get(opts, :live_product_path?))

  defp guardrails_ack_reason(operation, opts) do
    cond do
      operation in @live_operations and truthy?(Map.get(opts, :live_product_path?)) ->
        "live_product_path"

      operation in @mutating_operations ->
        "mutating_command"

      true ->
        "headless_guardrail"
    end
  end

  defp operation_envelope_name(operation),
    do: Map.get(@operation_envelope_names, operation, operation)

  defp product_opts(opts) do
    unique = unique_suffix()

    opts
    |> Map.take([:tenant_id, :pack_version])
    |> Map.put_new(:tenant_id, "extravaganza-headless-#{unique}")
    |> Map.put_new(:pack_version, "1.0.0-headless.#{unique}")
    |> Enum.to_list()
  end

  defp surface_opts(opts) do
    opts
    |> Map.take([:tenant_id, :pack_version])
    |> Enum.to_list()
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
               linear_api_key: trimmed
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
    with {:ok, apply_result} <- HeadlessSurface.apply_runtime_profile(runtime_profile, opts) do
      apply_readback = RuntimePresenter.present_profile_apply(apply_result)

      {:ok,
       reload
       |> Map.put("runtime_profile_apply", apply_readback)
       |> Map.put("runtime_profile_ref", apply_readback["profile_ref"])}
    end
  end

  defp apply_runtime_profile_to_reload(reload, _opts), do: {:ok, reload}

  defp runtime_request(opts) do
    opts
    |> Map.take([:cursor, :limit, :logs_root, :trace_id])
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp parse_env_assignment(assignment) when is_binary(assignment) do
    case String.split(assignment, "=", parts: 2) do
      [key, value] when key != "" -> %{key => value}
      _other -> %{}
    end
  end

  defp split_csv(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp truthy?(value), do: value not in [nil, false]

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
