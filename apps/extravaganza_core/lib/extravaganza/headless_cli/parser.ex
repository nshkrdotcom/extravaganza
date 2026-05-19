defmodule Extravaganza.HeadlessCLI.Parser do
  @moduledoc false

  @guardrails_ack_flags [
    "--ack-headless-guardrails",
    "--i-understand-that-this-will-be-running-without-the-usual-guardrails"
  ]

  @spec parse([String.t()]) :: map()
  def parse(argv) when is_list(argv), do: parse(argv, %{positionals: []})

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

  defp parse(["--skip-app-start" | rest], opts),
    do: parse(rest, Map.put(opts, :skip_app_start?, true))

  defp parse(["--temporal-status", temporal_status | rest], opts),
    do: parse(rest, Map.put(opts, :temporal_status, temporal_status))

  defp parse(["--source-binding-ref", source_binding_ref | rest], opts),
    do:
      parse(
        rest,
        Map.update(
          opts,
          :source_binding_refs,
          [source_binding_ref],
          &(&1 ++ [source_binding_ref])
        )
      )

  defp parse(["--source-binding-refs", source_binding_refs | rest], opts),
    do:
      parse(
        rest,
        Map.update(
          opts,
          :source_binding_refs,
          split_csv(source_binding_refs),
          &(split_csv(source_binding_refs) ++ &1)
        )
      )

  defp parse(["--credential-refs", credential_refs | rest], opts),
    do:
      parse(
        rest,
        Map.update(
          opts,
          :credential_refs,
          split_csv(credential_refs),
          &(split_csv(credential_refs) ++ &1)
        )
      )

  defp parse(["--confirm-no-active-lower-runs" | rest], opts),
    do: parse(rest, Map.put(opts, :confirm_no_active_lower_runs?, true))

  defp parse(["--active-lower-run-ref", active_lower_run_ref | rest], opts),
    do:
      parse(
        rest,
        Map.update(
          opts,
          :active_lower_run_refs,
          [active_lower_run_ref],
          &(&1 ++ [active_lower_run_ref])
        )
      )

  defp parse(["--active-lower-run-refs", active_lower_run_refs | rest], opts),
    do:
      parse(
        rest,
        Map.update(
          opts,
          :active_lower_run_refs,
          split_csv(active_lower_run_refs),
          &(split_csv(active_lower_run_refs) ++ &1)
        )
      )

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

  defp parse([flag | rest], opts) when flag in @guardrails_ack_flags,
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
end
