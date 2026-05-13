defmodule Extravaganza.SymphonyWorkflowImportTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Extravaganza.{HeadlessCLI, SymphonyWorkflowImport}

  @secret "linear-secret-from-test"

  @tag :tmp_dir
  test "loads explicit workflow front matter into a redacted product profile", %{tmp_dir: tmp_dir} do
    workflow_path = write_workflow!(tmp_dir, valid_workflow())

    assert {:ok, profile} =
             SymphonyWorkflowImport.profile(
               workflow_path: workflow_path,
               env: %{"LINEAR_API_KEY" => @secret, "LINEAR_ASSIGNEE" => "user:alice"}
             )

    assert profile["source"] == "symphony_workflow"
    assert profile["workflow"]["path"] == workflow_path

    assert profile["workflow"]["prompt_template"] ==
             "Ship {{ issue.identifier }} on attempt {{ attempt }}"

    assert profile["workflow"]["prompt_hash"] =~ "sha256:"

    assert profile["config"]["tracker"]["kind"] == "linear"
    assert profile["config"]["tracker"]["endpoint"] == "https://api.linear.app/graphql"
    assert profile["config"]["tracker"]["api_key_ref"] == "env://LINEAR_API_KEY"
    assert profile["config"]["tracker"]["api_key_supplied?"] == true
    assert profile["config"]["tracker"]["project_slug"] == "ENG"
    assert profile["config"]["tracker"]["assignee"] == "user:alice"
    assert profile["config"]["tracker"]["active_states"] == ["Todo", "Ready"]
    assert profile["config"]["tracker"]["terminal_states"] == ["Done"]

    assert profile["config"]["workspace"]["root"] ==
             Path.expand("relative_workspaces", tmp_dir)

    assert profile["config"]["agent"]["max_concurrent_agents"] == 10
    assert profile["config"]["agent"]["max_turns"] == 7
    assert profile["config"]["agent"]["max_retry_backoff_ms"] == 300_000
    assert profile["config"]["agent"]["max_concurrent_agents_by_state"] == %{"todo" => 2}

    assert profile["config"]["codex"]["command"] == "codex app-server"
    assert profile["config"]["codex"]["thread_sandbox"] == "workspace-write"

    assert profile["config"]["codex"]["turn_sandbox_policy"] == %{
             "type" => "workspaceWrite",
             "writableRoots" => [Path.expand("relative_workspaces", tmp_dir)],
             "readOnlyAccess" => %{"type" => "fullAccess"},
             "networkAccess" => false,
             "excludeTmpdirEnvVar" => false,
             "excludeSlashTmp" => false
           }

    assert profile["config"]["codex"]["turn_timeout_ms"] == 3_600_000
    assert profile["config"]["codex"]["read_timeout_ms"] == 5_000
    assert profile["config"]["codex"]["stall_timeout_ms"] == 300_000
    assert profile["config"]["hooks"]["timeout_ms"] == 12_345

    app_kit_profile = profile["app_kit_runtime_profile"]
    assert app_kit_profile["program"]["slug"] == "symphony-workflow"
    assert app_kit_profile["program"]["configuration"]["tracker"]["project_slug"] == "ENG"
    assert app_kit_profile["policy_bundle"]["metadata"]["prompt_hash"] =~ "sha256:"
    assert app_kit_profile["work_class"]["default_run_profile"]["max_turns"] == 7

    assert app_kit_profile["work_class"]["default_run_profile"]["codex_command"] ==
             "codex app-server"

    assert app_kit_profile["work_class"]["default_run_profile"]["turn_sandbox_policy"] ==
             profile["config"]["codex"]["turn_sandbox_policy"]

    assert app_kit_profile["placement_profile"]["workspace_policy"]["root"] ==
             Path.expand("relative_workspaces", tmp_dir)

    assert app_kit_profile["placement_profile"]["runtime_preferences"]["thread_sandbox"] ==
             "workspace-write"

    assert app_kit_profile["placement_profile"]["runtime_preferences"]["worker"] == %{
             "ssh_hosts" => ["worker-a", "worker-b"],
             "max_concurrent_agents_per_host" => 2
           }

    refute inspect(profile) =~ @secret
  end

  @tag :tmp_dir
  test "loads default WORKFLOW.md from supplied cwd and supports prompt-only files", %{
    tmp_dir: tmp_dir
  } do
    workflow_path = Path.join(tmp_dir, "WORKFLOW.md")
    File.write!(workflow_path, "Plain prompt body\n")

    assert {:ok, loaded} = SymphonyWorkflowImport.load(cwd: tmp_dir, env: %{})

    assert loaded.path == workflow_path
    assert loaded.config == %{}
    assert loaded.prompt_template == "Plain prompt body"
  end

  @tag :tmp_dir
  test "uses Symphony error names for workflow load and parse failures", %{tmp_dir: tmp_dir} do
    missing_path = Path.join(tmp_dir, "missing.md")

    assert {:error, {:missing_workflow_file, ^missing_path, :enoent}} =
             SymphonyWorkflowImport.load(workflow_path: missing_path, env: %{})

    non_map_path = write_workflow!(tmp_dir, "---\n- not\n- a\n- map\n---\nPrompt")

    assert {:error, :workflow_front_matter_not_a_map} =
             SymphonyWorkflowImport.load(workflow_path: non_map_path, env: %{})

    malformed_path = write_workflow!(tmp_dir, "---\ntracker: [unterminated\n---\nPrompt")

    assert {:error, {:workflow_parse_error, _reason}} =
             SymphonyWorkflowImport.load(workflow_path: malformed_path, env: %{})
  end

  @tag :tmp_dir
  test "validates dispatch-critical config without ambient environment reads", %{tmp_dir: tmp_dir} do
    workflow_path = write_workflow!(tmp_dir, valid_workflow())

    assert {:error, :missing_linear_api_token} =
             SymphonyWorkflowImport.validate(workflow_path: workflow_path, env: %{})

    assert :ok =
             SymphonyWorkflowImport.validate(
               workflow_path: workflow_path,
               env: %{"LINEAR_API_KEY" => @secret}
             )

    invalid_path =
      write_workflow!(tmp_dir, """
      ---
      tracker:
        kind: unsupported
        api_key: inline
        project_slug: ENG
      ---
      Prompt
      """)

    assert {:error, {:unsupported_tracker_kind, "unsupported"}} =
             SymphonyWorkflowImport.validate(workflow_path: invalid_path, env: %{})
  end

  @tag :tmp_dir
  test "rejects invalid typed config instead of silently defaulting", %{tmp_dir: tmp_dir} do
    invalid_path =
      write_workflow!(tmp_dir, """
      ---
      tracker:
        kind: memory
        active_states: [Todo, 1]
        terminal_states: done
      polling:
        interval_ms: 0
      worker:
        max_concurrent_agents_per_host: 0
      agent:
        max_concurrent_agents: 0
        max_turns: 0
        max_retry_backoff_ms: 0
        max_concurrent_agents_by_state:
          Todo: 0
      codex:
        command: ""
        turn_sandbox_policy: invalid
        turn_timeout_ms: 0
        read_timeout_ms: -1
        stall_timeout_ms: -1
      hooks:
        timeout_ms: 0
      observability:
        refresh_ms: 0
        render_interval_ms: 0
      server:
        port: -1
      ---
      Prompt
      """)

    assert {:error, {:invalid_workflow_config, message}} =
             SymphonyWorkflowImport.profile(workflow_path: invalid_path, env: %{})

    assert message =~ "polling.interval_ms"
    assert message =~ "tracker.active_states"
    assert message =~ "tracker.terminal_states"
    assert message =~ "worker.max_concurrent_agents_per_host"
    assert message =~ "agent.max_concurrent_agents"
    assert message =~ "agent.max_turns"
    assert message =~ "agent.max_retry_backoff_ms"
    assert message =~ "agent.max_concurrent_agents_by_state"
    assert message =~ "codex.command"
    assert message =~ "codex.turn_sandbox_policy"
    assert message =~ "codex.turn_timeout_ms"
    assert message =~ "codex.read_timeout_ms"
    assert message =~ "codex.stall_timeout_ms"
    assert message =~ "hooks.timeout_ms"
    assert message =~ "observability.refresh_ms"
    assert message =~ "observability.render_interval_ms"
    assert message =~ "server.port"
  end

  @tag :tmp_dir
  test "profile reload keeps last known good profile on invalid reload", %{tmp_dir: tmp_dir} do
    workflow_path = write_workflow!(tmp_dir, valid_workflow())
    cache_path = Path.join(tmp_dir, "last-good-profile.json")

    assert {:ok, reloaded} =
             SymphonyWorkflowImport.reload(
               workflow_path: workflow_path,
               profile_cache_path: cache_path,
               env: %{"LINEAR_API_KEY" => @secret}
             )

    assert reloaded["status"] == "reloaded"
    assert reloaded["last_known_good"]["status"] == "updated"
    assert reloaded["profile"]["workflow"]["prompt_template"] =~ "Ship"

    File.write!(workflow_path, "---\ntracker: [unterminated\n---\nBroken prompt\n")

    assert {:ok, failed_reload} =
             SymphonyWorkflowImport.reload(
               workflow_path: workflow_path,
               profile_cache_path: cache_path,
               env: %{"LINEAR_API_KEY" => @secret}
             )

    assert failed_reload["status"] == "reload_failed"
    assert failed_reload["error"]["code"] == "workflow_parse_error"
    assert failed_reload["last_known_good"]["workflow"]["prompt_template"] =~ "Ship"
    refute inspect(failed_reload) =~ @secret

    File.rm!(workflow_path)

    assert {:ok, missing_reload} =
             SymphonyWorkflowImport.reload(
               workflow_path: workflow_path,
               profile_cache_path: cache_path,
               env: %{"LINEAR_API_KEY" => @secret}
             )

    assert missing_reload["status"] == "reload_failed"
    assert missing_reload["error"]["code"] == "missing_workflow_file"
    assert missing_reload["last_known_good"]["workflow"]["prompt_template"] =~ "Ship"
  end

  @tag :tmp_dir
  test "renders Symphony workflow prompt with strict Solid variables", %{tmp_dir: tmp_dir} do
    workflow_path =
      write_workflow!(tmp_dir, """
      ---
      tracker:
        kind: memory
      ---
      Ticket {{ issue.identifier }} {{ issue.title }} labels={{ issue.labels }} created={{ issue.created_at }}
      {% if attempt %}Retry attempt {{ attempt }}{% endif %}
      {% if issue.description %}{{ issue.description }}{% else %}No description provided.{% endif %}
      """)

    created_at = DateTime.from_naive!(~N[2026-02-26 18:06:48], "Etc/UTC")

    assert {:ok, prompt} =
             SymphonyWorkflowImport.render_prompt(
               workflow_path: workflow_path,
               issue: %{
                 identifier: "MT-701",
                 title: "Render prompt",
                 labels: ["backend"],
                 created_at: created_at,
                 description: nil
               },
               attempt: 2
             )

    assert prompt =~ "Ticket MT-701 Render prompt labels=backend"
    assert prompt =~ "created=2026-02-26T18:06:48Z"
    assert prompt =~ "Retry attempt 2"
    assert prompt =~ "No description provided."
  end

  @tag :tmp_dir
  test "prompt rendering uses Symphony default and surfaces strict template errors", %{
    tmp_dir: tmp_dir
  } do
    blank_path =
      write_workflow!(tmp_dir, """
      ---
      tracker:
        kind: memory
      ---

      """)

    assert {:ok, default_prompt} =
             SymphonyWorkflowImport.render_prompt(
               workflow_path: blank_path,
               issue: %{identifier: "MT-778", title: "Handle empty body", description: nil}
             )

    assert default_prompt =~ "You are working on a Linear issue."
    assert default_prompt =~ "Identifier: MT-778"
    assert default_prompt =~ "Title: Handle empty body"
    assert default_prompt =~ "No description provided."

    unknown_variable_path =
      write_workflow!(tmp_dir, """
      ---
      tracker:
        kind: memory
      ---
      Work on {{ missing.ticket_id }}
      """)

    assert {:error, {:template_render_error, _message}} =
             SymphonyWorkflowImport.render_prompt(
               workflow_path: unknown_variable_path,
               issue: %{identifier: "MT-779"}
             )

    invalid_template_path =
      write_workflow!(tmp_dir, """
      ---
      tracker:
        kind: memory
      ---
      {% if issue.identifier %}
      """)

    assert {:error, {:template_parse_error, _message}} =
             SymphonyWorkflowImport.render_prompt(
               workflow_path: invalid_template_path,
               issue: %{identifier: "MT-780"}
             )
  end

  @tag :tmp_dir
  test "headless CLI exposes profile operations and redacted validation envelopes", %{
    tmp_dir: tmp_dir
  } do
    workflow_path = write_workflow!(tmp_dir, valid_workflow())

    assert :profile in HeadlessCLI.operations()
    assert :profile_validate in HeadlessCLI.operations()
    assert :profile_reload in HeadlessCLI.operations()

    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:profile_validate, [
                   "--json",
                   "--workflow",
                   workflow_path,
                   "--env",
                   "LINEAR_API_KEY=#{@secret}",
                   "--trace-id",
                   "trace:profile"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "profile_validate"
    assert decoded["data"]["status"] == "valid"

    assert decoded["data"]["profile"]["config"]["tracker"]["api_key_ref"] ==
             "env://LINEAR_API_KEY"

    refute output =~ @secret
  end

  defp write_workflow!(tmp_dir, body) do
    path = Path.join(tmp_dir, "WORKFLOW-#{System.unique_integer([:positive])}.md")
    File.write!(path, body)
    path
  end

  defp valid_workflow do
    """
    ---
    tracker:
      kind: linear
      api_key: $LINEAR_API_KEY
      project_slug: ENG
      active_states:
        - Todo
        - Ready
      terminal_states:
        - Done
    workspace:
      root: relative_workspaces
    worker:
      ssh_hosts:
        - worker-a
        - worker-b
      max_concurrent_agents_per_host: 2
    agent:
      max_turns: 7
      max_concurrent_agents_by_state:
        Todo: 2
    codex:
      command: codex app-server
    hooks:
      timeout_ms: 12345
    ---
    Ship {{ issue.identifier }} on attempt {{ attempt }}
    """
  end
end
