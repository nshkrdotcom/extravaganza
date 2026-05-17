defmodule Extravaganza.SymphonyWorkflowImport do
  @moduledoc """
  Product-safe importer for Symphony-style `WORKFLOW.md` files.

  The importer preserves Symphony's file/front-matter/config behavior without
  reading ambient OS environment variables. Callers must provide an explicit
  env map when `$VAR` indirection should be resolved.
  """

  alias Extravaganza.PolicyPresets.DefaultCodingOps

  @workflow_file_name "WORKFLOW.md"
  @continuation_retry_delay_ms 1_000
  @failure_retry_base_ms 10_000
  @default_linear_endpoint "https://api.linear.app/graphql"
  @default_active_states ["Todo", "In Progress"]
  @default_terminal_states ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
  @default_workspace_root Path.join("/tmp", "symphony_workspaces")
  @default_hook_timeout_ms 60_000
  @solid_render_opts [strict_variables: true, strict_filters: true]

  @default_prompt_template """
  You are working on a Linear issue.

  Identifier: {{ issue.identifier }}
  Title: {{ issue.title }}

  Body:
  {% if issue.description %}
  {{ issue.description }}
  {% else %}
  No description provided.
  {% endif %}
  """

  @default_approval_policy %{
    "reject" => %{
      "sandbox_approval" => true,
      "rules" => true,
      "mcp_elicitations" => true
    }
  }

  @type loaded_workflow :: %{
          path: Path.t(),
          config: map(),
          prompt: String.t(),
          prompt_template: String.t()
        }

  @spec default_workflow_path(keyword() | map()) :: Path.t()
  def default_workflow_path(opts \\ []) do
    opts
    |> opt(:cwd, File.cwd!())
    |> Path.join(@workflow_file_name)
  end

  @spec load(keyword() | map()) :: {:ok, loaded_workflow()} | {:error, term()}
  def load(opts \\ []) do
    path = workflow_path(opts)

    case File.read(path) do
      {:ok, content} ->
        parse(content, path)

      {:error, reason} ->
        {:error, {:missing_workflow_file, path, reason}}
    end
  end

  @spec profile(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def profile(opts \\ []) do
    with {:ok, loaded} <- load(opts),
         {:ok, config} <- normalized_config(loaded, env(opts)) do
      future_work_policy = future_work_policy(config, loaded)

      {:ok,
       %{
         "source" => "symphony_workflow",
         "workflow" => %{
           "path" => loaded.path,
           "prompt_template" => loaded.prompt_template,
           "prompt_hash" => prompt_hash(loaded.prompt_template)
         },
         "config" => config,
         "future_work_policy" => future_work_policy,
         "runtime_policy_config" => runtime_policy_config(config, future_work_policy),
         "runtime_profile" => runtime_profile(config),
         "app_kit_runtime_profile" => app_kit_runtime_profile(config, loaded),
         "validation" => validation_summary(config)
       }}
    end
  end

  @spec validate(keyword() | map()) :: :ok | {:error, term()}
  def validate(opts \\ []) do
    with {:ok, profile} <- profile(opts) do
      validate_profile(profile)
    end
  end

  @spec render_prompt(keyword() | map()) :: {:ok, String.t()} | {:error, term()}
  def render_prompt(opts \\ []) do
    with {:ok, loaded} <- load(opts) do
      loaded.prompt_template
      |> default_prompt()
      |> render_solid_prompt(%{
        "attempt" => opt(opts, :attempt),
        "issue" => opts |> opt(:issue, %{}) |> to_solid_value(),
        "workflow" => %{
          "path" => loaded.path,
          "config" => loaded.config,
          "prompt_hash" => prompt_hash(loaded.prompt_template)
        }
      })
    end
  end

  @spec reload(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def reload(opts \\ []) do
    cache_path = profile_cache_path(opts)

    case profile(opts) do
      {:ok, profile} ->
        validate_reload_profile(profile, cache_path)

      {:error, reason} ->
        reload_failure(reason, cache_path)
    end
  end

  @spec reload_status(keyword() | map()) :: map()
  def reload_status(opts \\ []) do
    opts
    |> profile_cache_path()
    |> read_reload_cache()
    |> case do
      {:ok, %{"reload_state" => state}} when is_map(state) ->
        state

      {:ok, %{"profile" => profile}} when is_map(profile) ->
        successful_reload_state(profile)

      {:error, :missing_last_known_good} ->
        %{
          "status" => "not_loaded",
          "last_known_good" => %{"status" => "missing"}
        }

      {:error, reason} ->
        %{
          "status" => "unavailable",
          "error" => sanitize_reload_reason(reason),
          "last_known_good" => %{"status" => "unavailable"}
        }
    end
  end

  @spec runtime_policy_config_from_cache(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def runtime_policy_config_from_cache(opts \\ []) do
    opts
    |> profile_cache_path()
    |> read_reload_cache()
    |> case do
      {:ok, %{"profile" => %{"runtime_policy_config" => policy_config}}}
      when is_map(policy_config) ->
        {:ok, policy_config}

      {:ok, %{"profile" => %{"config" => config} = profile}}
      when is_map(config) ->
        policy = future_work_policy_from_cached_profile(config, profile)
        {:ok, runtime_policy_config(config, policy)}

      {:ok, _payload} ->
        {:error, :invalid_last_known_good}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec record_runtime_profile_apply(map(), keyword() | map()) :: :ok | {:error, term()}
  def record_runtime_profile_apply(reload, opts \\ [])

  def record_runtime_profile_apply(
        %{"status" => "reloaded", "profile" => profile} = reload,
        opts
      )
      when is_map(profile) do
    state =
      profile
      |> successful_reload_state()
      |> put_runtime_profile_apply(Map.get(reload, "runtime_profile_apply"))

    write_reload_cache(profile_cache_path(opts), %{"profile" => profile, "reload_state" => state})
  end

  def record_runtime_profile_apply(_reload, _opts), do: :ok

  defp validate_reload_profile(profile, cache_path) do
    case validate_profile(profile) do
      :ok -> reload_success(profile, cache_path)
      {:error, reason} -> reload_failure(reason, cache_path)
    end
  end

  defp reload_success(profile, cache_path) do
    case write_last_known_good(cache_path, profile) do
      :ok -> {:ok, successful_reload_response(profile)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp successful_reload_response(profile) do
    %{
      "status" => "reloaded",
      "profile" => profile,
      "last_known_good" => %{
        "status" => "updated",
        "workflow_path" => profile["workflow"]["path"],
        "prompt_hash" => profile["workflow"]["prompt_hash"]
      }
    }
  end

  defp workflow_path(opts) do
    case opt(opts, :workflow_path) || opt(opts, :workflow) do
      path when is_binary(path) and path != "" -> Path.expand(path, opt(opts, :cwd, File.cwd!()))
      _other -> default_workflow_path(opts)
    end
  end

  defp parse(content, path) when is_binary(content) do
    {front_matter_lines, prompt_lines} = split_front_matter(content)

    case front_matter_yaml_to_map(front_matter_lines) do
      {:ok, front_matter} ->
        prompt = prompt_lines |> Enum.join("\n") |> String.trim()

        {:ok,
         %{
           path: path,
           config: front_matter,
           prompt: prompt,
           prompt_template: prompt
         }}

      {:error, :workflow_front_matter_not_a_map} ->
        {:error, :workflow_front_matter_not_a_map}

      {:error, reason} ->
        {:error, {:workflow_parse_error, reason}}
    end
  end

  defp split_front_matter(content) do
    lines = split_lines(content)

    case lines do
      ["---" | tail] ->
        {front, rest} = Enum.split_while(tail, &(&1 != "---"))

        case rest do
          ["---" | prompt_lines] -> {front, prompt_lines}
          _missing_close -> {front, []}
        end

      _other ->
        {[], lines}
    end
  end

  defp front_matter_yaml_to_map([]), do: {:ok, %{}}

  defp front_matter_yaml_to_map(lines) do
    yaml = Enum.join(lines, "\n")

    if String.trim(yaml) == "" do
      {:ok, %{}}
    else
      case YamlElixir.read_from_string(yaml) do
        {:ok, decoded} when is_map(decoded) -> {:ok, normalize_keys(decoded)}
        {:ok, _decoded} -> {:error, :workflow_front_matter_not_a_map}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp normalized_config(%{config: raw_config, path: path}, env) when is_map(raw_config) do
    base_dir = Path.dirname(path)

    case config_validation_errors(raw_config) do
      [] ->
        workspace = workspace_config(section(raw_config, "workspace"), env, base_dir)

        {:ok,
         %{
           "tracker" => tracker_config(section(raw_config, "tracker"), env),
           "polling" => polling_config(section(raw_config, "polling")),
           "workspace" => workspace,
           "worker" => worker_config(section(raw_config, "worker")),
           "agent" => agent_config(section(raw_config, "agent")),
           "codex" => codex_config(section(raw_config, "codex"), workspace),
           "hooks" => hooks_config(section(raw_config, "hooks")),
           "observability" => observability_config(section(raw_config, "observability")),
           "server" => server_config(section(raw_config, "server"))
         }}

      errors ->
        {:error, {:invalid_workflow_config, Enum.join(errors, ", ")}}
    end
  end

  defp tracker_config(config, env) do
    api_key = credential_ref(config["api_key"], env, "LINEAR_API_KEY", "tracker.api_key")

    %{
      "kind" => string_value(config["kind"]),
      "endpoint" => string_value(config["endpoint"], @default_linear_endpoint),
      "api_key_ref" => api_key.ref,
      "api_key_supplied?" => api_key.supplied?,
      "project_slug" => string_value(config["project_slug"]),
      "assignee" => env_string_value(config["assignee"], env, "LINEAR_ASSIGNEE"),
      "active_states" => string_list(config["active_states"], @default_active_states),
      "terminal_states" => string_list(config["terminal_states"], @default_terminal_states)
    }
  end

  defp polling_config(config) do
    %{"interval_ms" => positive_integer(config["interval_ms"], 30_000)}
  end

  defp workspace_config(config, env, base_dir) do
    root = string_value(config["root"])
    resolved = resolve_path_token(root, env, @default_workspace_root)

    %{"root" => expand_path(resolved, base_dir)}
  end

  defp worker_config(config) do
    %{
      "ssh_hosts" => string_list(config["ssh_hosts"], []),
      "max_concurrent_agents_per_host" =>
        maybe_positive_integer(config["max_concurrent_agents_per_host"])
    }
  end

  defp agent_config(config) do
    %{
      "max_concurrent_agents" => positive_integer(config["max_concurrent_agents"], 10),
      "max_turns" => positive_integer(config["max_turns"], 20),
      "max_retry_backoff_ms" => positive_integer(config["max_retry_backoff_ms"], 300_000),
      "max_concurrent_agents_by_state" =>
        normalize_state_limits(config["max_concurrent_agents_by_state"])
    }
  end

  defp codex_config(config, workspace) do
    %{
      "command" => string_value(config["command"], "codex app-server"),
      "approval_policy" =>
        normalize_keys(Map.get(config, "approval_policy", @default_approval_policy)),
      "thread_sandbox" => string_value(config["thread_sandbox"], "workspace-write"),
      "turn_sandbox_policy" =>
        optional_map(config["turn_sandbox_policy"]) ||
          default_turn_sandbox_policy(workspace["root"]),
      "turn_timeout_ms" => positive_integer(config["turn_timeout_ms"], 3_600_000),
      "read_timeout_ms" => positive_integer(config["read_timeout_ms"], 5_000),
      "stall_timeout_ms" => non_negative_integer(config["stall_timeout_ms"], 300_000)
    }
  end

  defp hooks_config(config) do
    %{
      "after_create" => string_value(config["after_create"]),
      "before_run" => string_value(config["before_run"]),
      "after_run" => string_value(config["after_run"]),
      "before_remove" => string_value(config["before_remove"]),
      "timeout_ms" => positive_integer(config["timeout_ms"], @default_hook_timeout_ms)
    }
  end

  defp observability_config(config) do
    %{
      "dashboard_enabled" => boolean_value(config["dashboard_enabled"], true),
      "refresh_ms" => positive_integer(config["refresh_ms"], 1_000),
      "render_interval_ms" => positive_integer(config["render_interval_ms"], 16)
    }
  end

  defp server_config(config) do
    %{
      "port" => maybe_non_negative_integer(config["port"]),
      "host" => string_value(config["host"], "127.0.0.1")
    }
  end

  defp config_validation_errors(raw_config) when is_map(raw_config) do
    tracker = section(raw_config, "tracker")
    polling = section(raw_config, "polling")
    worker = section(raw_config, "worker")
    agent = section(raw_config, "agent")
    codex = section(raw_config, "codex")
    hooks = section(raw_config, "hooks")
    observability = section(raw_config, "observability")
    server = section(raw_config, "server")

    []
    |> require_string_list(tracker, "tracker.active_states")
    |> require_string_list(tracker, "tracker.terminal_states")
    |> require_positive_integer(polling, "polling.interval_ms")
    |> require_positive_integer(worker, "worker.max_concurrent_agents_per_host", optional?: true)
    |> require_positive_integer(agent, "agent.max_concurrent_agents")
    |> require_positive_integer(agent, "agent.max_turns")
    |> require_positive_integer(agent, "agent.max_retry_backoff_ms")
    |> require_positive_state_limits(agent, "agent.max_concurrent_agents_by_state")
    |> reject_blank_string(codex, "codex.command")
    |> require_positive_integer(codex, "codex.turn_timeout_ms")
    |> require_positive_integer(codex, "codex.read_timeout_ms")
    |> require_non_negative_integer(codex, "codex.stall_timeout_ms")
    |> require_map(codex, "codex.turn_sandbox_policy", optional?: true)
    |> require_positive_integer(hooks, "hooks.timeout_ms")
    |> require_positive_integer(observability, "observability.refresh_ms")
    |> require_positive_integer(observability, "observability.render_interval_ms")
    |> require_non_negative_integer(server, "server.port", optional?: true)
    |> Enum.reverse()
  end

  defp require_positive_integer(errors, config, path, opts \\ []) do
    field = field_name(path)

    case Map.get(config, field) do
      nil ->
        errors

      "" ->
        errors

      value ->
        case integer_value(value) do
          int when is_integer(int) and int > 0 ->
            errors

          _other ->
            [path <> " must be a positive integer" | errors]
        end
    end
    |> maybe_required_field(config, path, opts)
  end

  defp require_non_negative_integer(errors, config, path, opts \\ []) do
    field = field_name(path)

    case Map.get(config, field) do
      nil ->
        errors

      "" ->
        errors

      value ->
        case integer_value(value) do
          int when is_integer(int) and int >= 0 ->
            errors

          _other ->
            [path <> " must be a non-negative integer" | errors]
        end
    end
    |> maybe_required_field(config, path, opts)
  end

  defp require_string_list(errors, config, path) do
    field = field_name(path)

    case Map.get(config, field) do
      nil ->
        errors

      value when is_list(value) ->
        if Enum.all?(value, &is_binary/1),
          do: errors,
          else: [path <> " must be a list of strings" | errors]

      _other ->
        [path <> " must be a list of strings" | errors]
    end
  end

  defp require_map(errors, config, path, opts) do
    field = field_name(path)

    case Map.get(config, field) do
      nil ->
        errors

      value when is_map(value) ->
        errors

      _other ->
        [path <> " must be a map" | errors]
    end
    |> maybe_required_field(config, path, opts)
  end

  defp require_positive_state_limits(errors, config, path) do
    field = field_name(path)

    case Map.get(config, field) do
      nil ->
        errors

      value when is_map(value) ->
        invalid? =
          Enum.any?(value, fn {state, limit} ->
            to_string(state) == "" or
              not match?(int when is_integer(int) and int > 0, integer_value(limit))
          end)

        if invalid?,
          do: [path <> " limits must be positive integers with non-blank states" | errors],
          else: errors

      _other ->
        [path <> " must be a map" | errors]
    end
  end

  defp reject_blank_string(errors, config, path) do
    field = field_name(path)

    case Map.fetch(config, field) do
      {:ok, value} when not is_binary(value) ->
        [path <> " must be a string" | errors]

      {:ok, value} ->
        if String.trim(value) == "",
          do: [path <> " must not be blank" | errors],
          else: errors

      :error ->
        errors
    end
  end

  defp maybe_required_field(errors, config, path, opts) do
    if Keyword.get(opts, :optional?, false) do
      errors
    else
      field = field_name(path)

      case Map.get(config, field) do
        nil -> errors
        "" -> [path <> " must not be blank" | errors]
        _value -> errors
      end
    end
  end

  defp field_name(path), do: path |> String.split(".") |> List.last()

  defp validate_profile(profile) do
    config = profile["config"]
    tracker = config["tracker"]
    codex = config["codex"]

    cond do
      is_nil(tracker["kind"]) ->
        {:error, :missing_tracker_kind}

      tracker["kind"] not in ["linear", "memory"] ->
        {:error, {:unsupported_tracker_kind, tracker["kind"]}}

      tracker["kind"] == "linear" and tracker["api_key_supplied?"] != true ->
        {:error, :missing_linear_api_token}

      tracker["kind"] == "linear" and blank?(tracker["project_slug"]) ->
        {:error, :missing_linear_project_slug}

      blank?(codex["command"]) ->
        {:error, :missing_codex_command}

      true ->
        :ok
    end
  end

  defp validation_summary(config) do
    case validate_profile(%{"config" => config}) do
      :ok -> %{"status" => "valid"}
      {:error, reason} -> %{"status" => "invalid", "reason" => sanitize_reason(reason)}
    end
  end

  defp runtime_profile(config) do
    %{
      "runtime_profile_ref" => "codex_session",
      "runtime_profile_kind" => "temporal_local",
      "codex_command" => config["codex"]["command"],
      "thread_sandbox" => config["codex"]["thread_sandbox"],
      "turn_sandbox_policy" => config["codex"]["turn_sandbox_policy"],
      "max_turns" => config["agent"]["max_turns"],
      "max_retry_backoff_ms" => config["agent"]["max_retry_backoff_ms"],
      "workspace_root" => config["workspace"]["root"],
      "hook_timeout_ms" => config["hooks"]["timeout_ms"]
    }
  end

  defp app_kit_runtime_profile(config, loaded) do
    prompt_hash = prompt_hash(loaded.prompt_template)
    future_work_policy = future_work_policy(config, loaded)

    %{
      "program" => %{
        "slug" => "symphony-workflow",
        "name" => "Symphony workflow import",
        "product_family" => "extravaganza",
        "configuration" => %{
          "source" => "symphony_workflow",
          "workflow_path" => loaded.path,
          "prompt_hash" => prompt_hash,
          "tracker" => profile_tracker_config(config["tracker"]),
          "polling" => config["polling"],
          "future_work_policy" => future_work_policy
        },
        "metadata" => %{
          "managed_by" => "extravaganza_core",
          "profile" => "symphony_workflow",
          "workflow_path" => loaded.path
        }
      },
      "policy_bundle" => %{
        "name" => "symphony_workflow_policy",
        "version" => "1",
        "policy_kind" => "workflow_md",
        "body" => "symphony_workflow_prompt_hash=#{prompt_hash}",
        "source_ref" => "workflow://#{loaded.path}",
        "metadata" => %{
          "prompt_hash" => prompt_hash,
          "prompt_source" => "WORKFLOW.md"
        }
      },
      "work_class" => %{
        "name" => "symphony_coding_operations",
        "kind" => "workflow",
        "intake_schema" => %{
          "required" => ["identifier", "title"],
          "properties" => %{
            "identifier" => "string",
            "title" => "string",
            "description" => "string",
            "state" => "string",
            "url" => "string"
          }
        },
        "default_review_profile" => %{},
        "default_run_profile" => %{
          "runtime_profile_ref" => "codex_session",
          "runtime_profile_kind" => "temporal_local",
          "runtime_profile_revision" => 1,
          "runtime_class" => "session",
          "lower_runtime_kind" => "codex_session",
          "capability_id" => "codex.session.turn",
          "codex_command" => config["codex"]["command"],
          "approval_policy" => config["codex"]["approval_policy"],
          "thread_sandbox" => config["codex"]["thread_sandbox"],
          "turn_sandbox_policy" => config["codex"]["turn_sandbox_policy"],
          "turn_timeout_ms" => config["codex"]["turn_timeout_ms"],
          "read_timeout_ms" => config["codex"]["read_timeout_ms"],
          "stall_timeout_ms" => config["codex"]["stall_timeout_ms"],
          "max_turns" => config["agent"]["max_turns"],
          "max_retry_backoff_ms" => config["agent"]["max_retry_backoff_ms"]
        }
      },
      "placement_profile" => %{
        "profile_id" => "symphony_workflow_local",
        "strategy" => "local",
        "target_selector" => %{"target_ref" => "codex-default"},
        "runtime_preferences" => %{
          "codex_command" => config["codex"]["command"],
          "thread_sandbox" => config["codex"]["thread_sandbox"],
          "turn_sandbox_policy" => config["codex"]["turn_sandbox_policy"],
          "worker" => config["worker"]
        },
        "workspace_policy" => %{
          "strategy" => "per_subject",
          "reuse" => true,
          "cleanup" => "on_terminal",
          "root" => config["workspace"]["root"],
          "hooks" => config["hooks"]
        },
        "metadata" => %{
          "tracker_active_states" => config["tracker"]["active_states"],
          "tracker_terminal_states" => config["tracker"]["terminal_states"],
          "polling_interval_ms" => config["polling"]["interval_ms"],
          "max_concurrent_agents" => config["agent"]["max_concurrent_agents"],
          "max_concurrent_agents_by_state" => config["agent"]["max_concurrent_agents_by_state"],
          "future_work_policy_ref" => future_work_policy["policy_ref"],
          "remote_workspace_semantics" => remote_workspace_semantics(config)
        }
      }
    }
  end

  defp remote_workspace_semantics(config) do
    worker = config["worker"] || %{}

    %{
      "source" => "symphony.worker",
      "replacement" => "mezzanine_runtime_placement",
      "ssh_command_execution" => "delegated_to_governed_runtime_placement",
      "workspace_path_semantics" => "logical_workspace_ref_plus_runtime_file_scope",
      "direct_product_ssh" => false,
      "ssh_hosts" => worker["ssh_hosts"] || [],
      "max_concurrent_agents_per_host" => worker["max_concurrent_agents_per_host"]
    }
  end

  defp profile_tracker_config(tracker) do
    tracker
    |> Map.drop(["api_key_supplied?"])
    |> Map.put("api_key_ref", tracker["api_key_ref"])
  end

  defp future_work_policy(config, loaded) do
    prompt_hash = prompt_hash(loaded.prompt_template)

    %{
      "policy_ref" => "future-work-policy://symphony-workflow/#{hash_suffix(prompt_hash)}",
      "source" => "symphony_workflow",
      "workflow" => %{
        "path" => loaded.path,
        "prompt_hash" => prompt_hash
      },
      "scope" => %{
        "applies_to" => "future_work_only",
        "mutates_active_runs?" => false
      },
      "source_admission" => %{
        "tracker_kind" => config["tracker"]["kind"],
        "endpoint" => config["tracker"]["endpoint"],
        "api_key_ref" => config["tracker"]["api_key_ref"],
        "project_slug" => config["tracker"]["project_slug"],
        "assignee" => config["tracker"]["assignee"],
        "active_states" => config["tracker"]["active_states"],
        "terminal_states" => config["tracker"]["terminal_states"]
      },
      "polling" => config["polling"],
      "dispatch" => %{
        "max_concurrent_agents" => config["agent"]["max_concurrent_agents"],
        "max_concurrent_agents_by_state" => config["agent"]["max_concurrent_agents_by_state"],
        "max_concurrent_agents_per_host" => config["worker"]["max_concurrent_agents_per_host"],
        "worker_hosts" => config["worker"]["ssh_hosts"] || []
      },
      "codex" => Map.put(config["codex"], "max_turns", config["agent"]["max_turns"]),
      "workspace" => %{
        "root" => config["workspace"]["root"],
        "hooks" => config["hooks"],
        "remote_workspace_semantics" => remote_workspace_semantics(config)
      },
      "retry" => %{
        "strategy" => "symphony_exponential_backoff",
        "continuation_backoff_ms" => @continuation_retry_delay_ms,
        "failure_base_backoff_ms" => @failure_retry_base_ms,
        "max_retry_backoff_ms" => config["agent"]["max_retry_backoff_ms"]
      }
    }
  end

  defp future_work_policy_from_cached_profile(config, profile) do
    case Map.get(profile, "future_work_policy") do
      policy when is_map(policy) ->
        policy

      _other ->
        loaded = %{
          path: get_in(profile, ["workflow", "path"]) || @workflow_file_name,
          prompt_template: get_in(profile, ["workflow", "prompt_template"]) || ""
        }

        future_work_policy(config, loaded)
    end
  end

  defp runtime_policy_config(config, future_work_policy) do
    default_config = DefaultCodingOps.runtime_config()

    default_config
    |> Map.put("tracker", profile_tracker_config(config["tracker"]))
    |> Map.put("polling", config["polling"])
    |> Map.put("worker", config["worker"])
    |> Map.put("agent", config["agent"])
    |> Map.put("codex", config["codex"])
    |> Map.put("hooks", config["hooks"])
    |> Map.put(
      "workspace",
      Map.merge(Map.get(default_config, "workspace", %{}), config["workspace"])
    )
    |> Map.put("retry", runtime_retry_config(default_config, config))
    |> Map.put("future_work_policy", future_work_policy)
  end

  defp runtime_retry_config(default_config, config) do
    default_config
    |> Map.get("retry", %{})
    |> Map.merge(%{
      "strategy" => "symphony_exponential_backoff",
      "continuation_backoff_ms" => @continuation_retry_delay_ms,
      "failure_base_backoff_ms" => @failure_retry_base_ms,
      "max_backoff_ms" => config["agent"]["max_retry_backoff_ms"],
      "max_retry_backoff_ms" => config["agent"]["max_retry_backoff_ms"]
    })
  end

  defp hash_suffix("sha256:" <> digest), do: digest
  defp hash_suffix(value), do: to_string(value)

  defp render_solid_prompt(template, assigns) do
    with {:ok, parsed} <- parse_solid_template(template) do
      try do
        rendered =
          parsed
          |> Solid.render!(assigns, @solid_render_opts)
          |> IO.iodata_to_binary()

        {:ok, rendered}
      rescue
        error -> {:error, {:template_render_error, Exception.message(error)}}
      end
    end
  end

  defp parse_solid_template(template) do
    {:ok, Solid.parse!(template)}
  rescue
    error -> {:error, {:template_parse_error, Exception.message(error)}}
  end

  defp default_prompt(prompt) when is_binary(prompt) do
    if String.trim(prompt) == "", do: @default_prompt_template, else: prompt
  end

  defp to_solid_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp to_solid_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp to_solid_value(%Date{} = value), do: Date.to_iso8601(value)
  defp to_solid_value(%Time{} = value), do: Time.to_iso8601(value)
  defp to_solid_value(%_{} = value), do: value |> Map.from_struct() |> to_solid_value()

  defp to_solid_value(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), to_solid_value(nested)} end)
  end

  defp to_solid_value(value) when is_list(value), do: Enum.map(value, &to_solid_value/1)
  defp to_solid_value(value), do: value

  defp profile_cache_path(opts) do
    case opt(opts, :profile_cache_path) || opt(opts, :cache_path) do
      path when is_binary(path) and path != "" ->
        Path.expand(path, opt(opts, :cwd, File.cwd!()))

      _other ->
        workflow_path = workflow_path(opts)
        Path.join(Path.dirname(workflow_path), ".extravaganza_symphony_profile_last_good.json")
    end
  end

  defp write_last_known_good(cache_path, profile) do
    write_reload_cache(cache_path, %{
      "profile" => profile,
      "reload_state" => successful_reload_state(profile)
    })
  end

  defp reload_failure(reason, cache_path) do
    case read_last_known_good(cache_path) do
      {:ok, profile} ->
        reload_state = failed_reload_state(reason, profile)

        case write_reload_cache(cache_path, %{
               "profile" => profile,
               "reload_state" => reload_state
             }) do
          :ok ->
            {:ok,
             %{
               "status" => "reload_failed",
               "error" => sanitize_reason(reason),
               "last_known_good" => profile
             }}

          {:error, write_reason} ->
            {:error, write_reason}
        end

      {:error, :missing_last_known_good} ->
        {:error, reason}

      {:error, _reason} ->
        {:error, reason}
    end
  end

  defp read_last_known_good(cache_path) do
    case read_reload_cache(cache_path) do
      {:ok, %{"profile" => profile}} -> {:ok, profile}
      {:ok, _other} -> {:error, :invalid_last_known_good}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_reload_cache(cache_path) do
    with {:ok, body} <- File.read(cache_path),
         {:ok, decoded} when is_map(decoded) <- Jason.decode(body) do
      {:ok, decoded}
    else
      {:error, :enoent} -> {:error, :missing_last_known_good}
      {:ok, _other} -> {:error, :invalid_last_known_good}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_reload_cache(cache_path, payload) do
    with :ok <- cache_path |> Path.dirname() |> File.mkdir_p(),
         :ok <- File.write(cache_path, Jason.encode!(payload)) do
      :ok
    else
      {:error, reason} -> {:error, {:profile_cache_write_failed, reason}}
    end
  end

  defp successful_reload_state(profile) do
    summary = reload_profile_summary(profile)

    %{
      "status" => "reloaded",
      "workflow_path" => summary["workflow_path"],
      "prompt_hash" => summary["prompt_hash"],
      "future_work_policy" => summary["future_work_policy"],
      "last_known_good" => Map.put(summary, "status", "updated")
    }
  end

  defp failed_reload_state(reason, profile) do
    %{
      "status" => "reload_failed",
      "error" => sanitize_reload_reason(reason),
      "last_known_good" => profile |> reload_profile_summary() |> Map.put("status", "available")
    }
  end

  defp reload_profile_summary(profile) do
    %{
      "workflow_path" => profile |> get_in(["workflow", "path"]) |> redact_path(),
      "prompt_hash" => get_in(profile, ["workflow", "prompt_hash"]),
      "future_work_policy" => Map.get(profile, "future_work_policy")
    }
  end

  defp put_runtime_profile_apply(state, apply_readback) when is_map(apply_readback) do
    state
    |> Map.put("runtime_profile_apply", apply_readback)
    |> Map.put("runtime_profile_ref", Map.get(apply_readback, "profile_ref"))
  end

  defp put_runtime_profile_apply(state, _apply_readback), do: state

  defp credential_ref(nil, env, default_env_name, _field) do
    case env_value(env, default_env_name) do
      nil -> %{ref: nil, supplied?: false}
      "" -> %{ref: nil, supplied?: false}
      _value -> %{ref: "env://#{default_env_name}", supplied?: true}
    end
  end

  defp credential_ref(value, env, default_env_name, field) when is_binary(value) do
    case env_reference_name(value) do
      {:ok, env_name} ->
        case env_value(env, env_name) do
          nil -> %{ref: "env://#{env_name}", supplied?: false}
          "" -> %{ref: "env://#{env_name}", supplied?: false}
          _value -> %{ref: "env://#{env_name}", supplied?: true}
        end

      :error ->
        if blank?(value) do
          credential_ref(nil, env, default_env_name, field)
        else
          %{ref: "inline://workflow/#{field}", supplied?: true}
        end
    end
  end

  defp resolve_path_token(nil, _env, default), do: default
  defp resolve_path_token("", _env, default), do: default

  defp resolve_path_token(value, env, default) when is_binary(value) do
    case env_reference_name(value) do
      {:ok, env_name} ->
        case env_value(env, env_name) do
          nil -> default
          "" -> default
          env_path -> env_path
        end

      :error ->
        value
    end
  end

  defp env_string_value(value, env, default_env_name) do
    env = normalize_env(env)

    case value do
      nil ->
        string_value(Map.get(env, default_env_name))

      "" ->
        string_value(Map.get(env, default_env_name))

      value when is_binary(value) ->
        case env_reference_name(value) do
          {:ok, env_name} -> string_value(Map.get(env, env_name))
          :error -> string_value(value)
        end

      value ->
        string_value(value)
    end
  end

  defp env_reference_name("$" <> env_name) do
    if valid_env_name?(env_name) do
      {:ok, env_name}
    else
      :error
    end
  end

  defp env_reference_name(_value), do: :error

  defp split_lines(content), do: split_lines(content, "", [])

  defp split_lines(<<>>, current, lines), do: Enum.reverse([current | lines])

  defp split_lines(<<"\r\n", rest::binary>>, current, lines),
    do: split_lines(rest, "", [current | lines])

  defp split_lines(<<"\n", rest::binary>>, current, lines),
    do: split_lines(rest, "", [current | lines])

  defp split_lines(<<"\r", rest::binary>>, current, lines),
    do: split_lines(rest, "", [current | lines])

  defp split_lines(<<char::utf8, rest::binary>>, current, lines) do
    split_lines(rest, current <> <<char::utf8>>, lines)
  end

  defp valid_env_name?(<<first::utf8, rest::binary>>) do
    env_name_start?(first) and valid_env_name_rest?(rest)
  end

  defp valid_env_name?(_value), do: false

  defp valid_env_name_rest?(<<>>), do: true

  defp valid_env_name_rest?(<<char::utf8, rest::binary>>) do
    env_name_part?(char) and valid_env_name_rest?(rest)
  end

  defp env_name_start?(char), do: ascii_letter?(char) or char == ?_
  defp env_name_part?(char), do: env_name_start?(char) or char in ?0..?9
  defp ascii_letter?(char), do: char in ?A..?Z or char in ?a..?z

  defp env_value(env, key) do
    env = normalize_env(env)
    Map.get(env, key)
  end

  defp normalize_env(env) when is_map(env) do
    Map.new(env, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_env(_env), do: %{}

  defp env(opts), do: opts |> opt(:env, %{}) |> normalize_env()

  defp section(config, key) when is_map(config) do
    case Map.get(config, key) do
      value when is_map(value) -> value
      _other -> %{}
    end
  end

  defp normalize_state_limits(value) when is_map(value) do
    Map.new(value, fn {state, limit} ->
      {String.downcase(to_string(state)), positive_integer(limit, 1)}
    end)
  end

  defp normalize_state_limits(_value), do: %{}

  defp normalize_keys(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), normalize_keys(nested)} end)
  end

  defp normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)
  defp normalize_keys(value), do: value

  defp string_value(value, default \\ nil)
  defp string_value(nil, default), do: default
  defp string_value("", default), do: default
  defp string_value(value, _default) when is_binary(value), do: value
  defp string_value(value, _default), do: to_string(value)

  defp string_list(value, _default) when is_list(value), do: Enum.map(value, &to_string/1)
  defp string_list(_value, default), do: default

  defp positive_integer(value, default) do
    case integer_value(value) do
      int when is_integer(int) and int > 0 -> int
      _other -> default
    end
  end

  defp non_negative_integer(value, default) do
    case integer_value(value) do
      int when is_integer(int) and int >= 0 -> int
      _other -> default
    end
  end

  defp maybe_positive_integer(value) do
    case integer_value(value) do
      int when is_integer(int) and int > 0 -> int
      _other -> nil
    end
  end

  defp maybe_non_negative_integer(value) do
    case integer_value(value) do
      int when is_integer(int) and int >= 0 -> int
      _other -> nil
    end
  end

  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _other -> nil
    end
  end

  defp integer_value(_value), do: nil

  defp boolean_value(value, _default) when is_boolean(value), do: value
  defp boolean_value(_value, default), do: default

  defp optional_map(value) when is_map(value), do: normalize_keys(value)
  defp optional_map(_value), do: nil

  defp default_turn_sandbox_policy(workspace_root) do
    %{
      "type" => "workspaceWrite",
      "writableRoots" => [workspace_root],
      "readOnlyAccess" => %{"type" => "fullAccess"},
      "networkAccess" => false,
      "excludeTmpdirEnvVar" => false,
      "excludeSlashTmp" => false
    }
  end

  defp expand_path(path, base_dir) when is_binary(path) do
    if Path.type(path) == :absolute, do: Path.expand(path), else: Path.expand(path, base_dir)
  end

  defp prompt_hash(prompt_template) do
    digest = :crypto.hash(:sha256, prompt_template)
    "sha256:" <> Base.encode16(digest, case: :lower)
  end

  defp sanitize_reason({reason, value}),
    do: %{"code" => to_string(reason), "value" => printable_reason_value(value)}

  defp sanitize_reason({:missing_workflow_file, path, raw_reason}) do
    %{
      "code" => "missing_workflow_file",
      "value" => printable_reason_value(path),
      "reason" => printable_reason_value(raw_reason)
    }
  end

  defp sanitize_reason(reason) when is_atom(reason) or is_binary(reason), do: to_string(reason)
  defp sanitize_reason(reason), do: inspect(reason)

  defp sanitize_reload_reason({:missing_workflow_file, path, raw_reason}) do
    %{
      "code" => "missing_workflow_file",
      "value" => redact_path(path),
      "reason" => printable_reason_value(raw_reason)
    }
  end

  defp sanitize_reload_reason(reason), do: sanitize_reason(reason)

  defp printable_reason_value(value) when is_binary(value), do: value
  defp printable_reason_value(value), do: inspect(value)

  defp redact_path(path) when is_binary(path) do
    if Path.type(path) == :absolute, do: "[redacted-path]", else: path
  end

  defp redact_path(path), do: printable_reason_value(path)

  defp blank?(value), do: is_nil(value) or value == ""

  defp opt(opts, key, default \\ nil)

  defp opt(opts, key, default) when is_map(opts) do
    Map.get(opts, key) || Map.get(opts, Atom.to_string(key)) || default
  end

  defp opt(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
end
