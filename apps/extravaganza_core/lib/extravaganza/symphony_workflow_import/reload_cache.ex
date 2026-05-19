defmodule Extravaganza.SymphonyWorkflowImport.ReloadCache do
  @moduledoc false

  alias Extravaganza.SymphonyWorkflowImport.{Document, RuntimeProfile, Validation}

  @spec profile_cache_path(keyword() | map()) :: Path.t()
  def profile_cache_path(opts) do
    case opt(opts, :profile_cache_path) || opt(opts, :cache_path) do
      path when is_binary(path) and path != "" ->
        Path.expand(path, opt(opts, :cwd, File.cwd!()))

      _other ->
        workflow_path = Document.workflow_path(opts)
        Path.join(Path.dirname(workflow_path), ".extravaganza_symphony_profile_last_good.json")
    end
  end

  @spec reload(keyword() | map(), {:ok, map()} | {:error, term()}, (map() ->
                                                                      :ok | {:error, term()})) ::
          {:ok, map()} | {:error, term()}
  def reload(opts, profile_result, validate_fun \\ &Validation.validate_profile/1)

  def reload(opts, {:ok, profile}, validate_fun) when is_function(validate_fun, 1) do
    cache_path = profile_cache_path(opts)

    case validate_fun.(profile) do
      :ok -> reload_success(profile, cache_path)
      {:error, reason} -> reload_failure(reason, cache_path)
    end
  end

  def reload(opts, {:error, reason}, _validate_fun) do
    opts
    |> profile_cache_path()
    |> then(&reload_failure(reason, &1))
  end

  @spec reload_status(keyword() | map()) :: map()
  def reload_status(opts) do
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
          "error" => Validation.sanitize_reload_reason(reason),
          "last_known_good" => %{"status" => "unavailable"}
        }
    end
  end

  @spec runtime_policy_config_from_cache(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def runtime_policy_config_from_cache(opts) do
    opts
    |> profile_cache_path()
    |> read_reload_cache()
    |> case do
      {:ok, %{"profile" => %{"runtime_policy_config" => policy_config}}}
      when is_map(policy_config) ->
        {:ok, policy_config}

      {:ok, %{"profile" => %{"config" => config} = profile}}
      when is_map(config) ->
        policy = RuntimeProfile.future_work_policy_from_cached_profile(config, profile)
        {:ok, RuntimeProfile.runtime_policy_config(config, policy)}

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
               "error" => Validation.sanitize_reason(reason),
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
      "error" => Validation.sanitize_reload_reason(reason),
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

  defp redact_path(path) when is_binary(path) do
    if Path.type(path) == :absolute, do: "[redacted-path]", else: path
  end

  defp redact_path(path), do: inspect(path)

  defp opt(opts, key, default \\ nil)

  defp opt(opts, key, default) when is_map(opts) do
    Map.get(opts, key) || Map.get(opts, Atom.to_string(key)) || default
  end

  defp opt(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
end
