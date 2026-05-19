defmodule Extravaganza.SymphonyWorkflowImport.RuntimeProfile do
  @moduledoc false

  alias Extravaganza.PolicyPresets.DefaultCodingOps

  @workflow_file_name "WORKFLOW.md"
  @continuation_retry_delay_ms 1_000
  @failure_retry_base_ms 10_000

  @spec runtime_profile(map()) :: map()
  def runtime_profile(config) do
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

  @spec app_kit_runtime_profile(map(), map()) :: map()
  def app_kit_runtime_profile(config, loaded) do
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

  @spec future_work_policy(map(), map()) :: map()
  def future_work_policy(config, loaded) do
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

  @spec future_work_policy_from_cached_profile(map(), map()) :: map()
  def future_work_policy_from_cached_profile(config, profile) do
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

  @spec runtime_policy_config(map(), map()) :: map()
  def runtime_policy_config(config, future_work_policy) do
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

  @spec prompt_hash(String.t()) :: String.t()
  def prompt_hash(prompt_template) do
    digest = :crypto.hash(:sha256, prompt_template)
    "sha256:" <> Base.encode16(digest, case: :lower)
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

  defp hash_suffix("sha256:" <> digest), do: digest
  defp hash_suffix(value), do: to_string(value)
end
