defmodule Extravaganza.SymphonyWorkflowImport.ConfigNormalizer do
  @moduledoc false

  @default_linear_endpoint "https://api.linear.app/graphql"
  @default_active_states ["Todo", "In Progress"]
  @default_terminal_states ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
  @default_workspace_root Path.join("/tmp", "symphony_workspaces")
  @default_hook_timeout_ms 60_000

  @default_approval_policy %{
    "reject" => %{
      "sandbox_approval" => true,
      "rules" => true,
      "mcp_elicitations" => true
    }
  }

  @spec normalized_config(map(), map()) :: {:ok, map()} | {:error, term()}
  def normalized_config(%{config: raw_config, path: path}, env) when is_map(raw_config) do
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

  @spec env(keyword() | map()) :: map()
  def env(opts), do: opts |> opt(:env, %{}) |> normalize_env()

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

  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp opt(opts, key, default)

  defp opt(opts, key, default) when is_map(opts) do
    Map.get(opts, key) || Map.get(opts, Atom.to_string(key)) || default
  end

  defp opt(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
end
