defmodule Extravaganza.HeadlessRuntimeSurfaceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AppKit.Core.RuntimeSurface.{
    LiveEffectReceipt,
    RuntimeLogPage,
    RuntimeProfileApplyResult,
    RuntimeStatusSnapshot
  }

  alias Extravaganza.{HeadlessCLI, HeadlessSurface}

  @secret "linear-secret-value"
  @guardrails_ack "--ack-headless-guardrails"

  setup do
    previous_runtime_backend = Application.get_env(:app_kit_core, :runtime_backend)
    previous_source_backend = Application.get_env(:app_kit_core, :source_backend)
    previous_fixture_context = Application.get_env(:extravaganza_core, :headless_fixture_context?)

    Application.put_env(:app_kit_core, :runtime_backend, __MODULE__.RuntimeBackend)
    Application.put_env(:app_kit_core, :source_backend, __MODULE__.SourceBackend)
    Application.put_env(:extravaganza_core, :headless_fixture_context?, true)

    on_exit(fn ->
      restore_env(:app_kit_core, :runtime_backend, previous_runtime_backend)
      restore_env(:app_kit_core, :source_backend, previous_source_backend)
      restore_env(:extravaganza_core, :headless_fixture_context?, previous_fixture_context)
    end)
  end

  @tag :tmp_dir
  test "profile reload applies the imported runtime profile through AppKit", %{tmp_dir: tmp_dir} do
    workflow_path = write_workflow!(tmp_dir)
    cache_path = Path.join(tmp_dir, "last-good-profile.json")

    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:profile_reload, [
                   "--json",
                   @guardrails_ack,
                   "--workflow",
                   workflow_path,
                   "--env",
                   "LINEAR_API_KEY=#{@secret}",
                   "--profile-cache",
                   cache_path,
                   "--trace-id",
                   "trace:profile-apply"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "profile_reload"
    assert decoded["data"]["status"] == "reloaded"
    assert decoded["data"]["runtime_profile_apply"]["status"] == "updated"

    assert decoded["data"]["runtime_profile_apply"]["profile_ref"] ==
             "runtime-profile://symphony-workflow"

    assert decoded["runtime_profile_ref"] == "runtime-profile://symphony-workflow"

    remote_semantics =
      decoded["data"]["profile"]["app_kit_runtime_profile"]["placement_profile"]["metadata"][
        "remote_workspace_semantics"
      ]

    app_kit_future_policy =
      decoded["data"]["profile"]["app_kit_runtime_profile"]["program"]["configuration"][
        "future_work_policy"
      ]

    assert app_kit_future_policy["source_admission"]["active_states"] == ["Todo", "In Progress"]
    assert app_kit_future_policy["scope"]["applies_to"] == "future_work_only"

    assert remote_semantics["replacement"] == "mezzanine_runtime_placement"

    assert remote_semantics["ssh_command_execution"] ==
             "delegated_to_governed_runtime_placement"

    assert remote_semantics["direct_product_ssh"] == false
    assert remote_semantics["ssh_hosts"] == ["worker-a"]
    refute output =~ @secret

    status_output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:status, [
                   "--json",
                   "--profile-cache",
                   cache_path,
                   "--trace-id",
                   "trace:profile-status"
                 ])
      end)

    status = Jason.decode!(status_output)
    workflow_reload = get_in(status, ["data", "data", "metadata", "workflow_reload"])

    assert status["ok"] == true
    assert status["operation"] == "status"
    assert workflow_reload["status"] == "reloaded"
    assert workflow_reload["workflow_path"] == "[redacted-path]"
    assert workflow_reload["prompt_hash"] == decoded["data"]["profile"]["workflow"]["prompt_hash"]
    assert workflow_reload["runtime_profile_ref"] == "runtime-profile://symphony-workflow"
    assert workflow_reload["runtime_profile_apply"]["status"] == "updated"
    refute status_output =~ @secret
  end

  @tag :tmp_dir
  test "profile reload exposes future work policy for later dispatch and retries", %{
    tmp_dir: tmp_dir
  } do
    workflow_path = write_future_policy_workflow!(tmp_dir)
    cache_path = Path.join(tmp_dir, "future-policy-last-good.json")

    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:profile_reload, [
                   "--json",
                   @guardrails_ack,
                   "--workflow",
                   workflow_path,
                   "--env",
                   "LINEAR_API_KEY=#{@secret}",
                   "--profile-cache",
                   cache_path,
                   "--trace-id",
                   "trace:future-policy-apply"
                 ])
      end)

    decoded = Jason.decode!(output)
    policy = get_in(decoded, ["data", "profile", "future_work_policy"])

    assert policy["scope"] == %{
             "applies_to" => "future_work_only",
             "mutates_active_runs?" => false
           }

    assert policy["source_admission"]["active_states"] == ["Ready", "In Progress"]
    assert policy["source_admission"]["terminal_states"] == ["Done", "Canceled"]
    assert policy["polling"]["interval_ms"] == 12_345
    assert policy["dispatch"]["max_concurrent_agents"] == 4
    assert policy["dispatch"]["max_concurrent_agents_by_state"] == %{"ready" => 2}
    assert policy["dispatch"]["max_concurrent_agents_per_host"] == 1
    assert policy["codex"]["command"] == "codex app-server --profile future"
    assert policy["codex"]["approval_policy"]["reject"]["sandbox_approval"] == false
    assert policy["codex"]["thread_sandbox"] == "danger-full-access"
    assert policy["codex"]["turn_sandbox_policy"]["type"] == "dangerFullAccess"
    assert policy["codex"]["turn_timeout_ms"] == 60_000
    assert policy["codex"]["read_timeout_ms"] == 7_000
    assert policy["codex"]["stall_timeout_ms"] == 9_000
    assert policy["workspace"]["root"] == "[redacted-path]"
    assert policy["workspace"]["hooks"]["before_run"] == "scripts/before_run.sh"
    assert policy["workspace"]["hooks"]["timeout_ms"] == 2_500
    assert policy["retry"]["failure_base_backoff_ms"] == 10_000
    assert policy["retry"]["continuation_backoff_ms"] == 1_000
    assert policy["retry"]["max_retry_backoff_ms"] == 44_000

    status_output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:status, [
                   "--json",
                   "--profile-cache",
                   cache_path,
                   "--trace-id",
                   "trace:future-policy-status"
                 ])
      end)

    status_policy =
      get_in(Jason.decode!(status_output), [
        "data",
        "data",
        "metadata",
        "workflow_reload",
        "future_work_policy"
      ])

    assert status_policy == policy
    refute output =~ @secret
    refute status_output =~ @secret
  end

  @tag :tmp_dir
  test "status exposes failed profile reload while keeping the last known good profile", %{
    tmp_dir: tmp_dir
  } do
    workflow_path = write_workflow!(tmp_dir)
    cache_path = Path.join(tmp_dir, "last-good-profile.json")

    initial_output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:profile_reload, [
                   "--json",
                   @guardrails_ack,
                   "--workflow",
                   workflow_path,
                   "--env",
                   "LINEAR_API_KEY=#{@secret}",
                   "--profile-cache",
                   cache_path,
                   "--trace-id",
                   "trace:profile-apply"
                 ])
      end)

    initial = Jason.decode!(initial_output)

    File.write!(workflow_path, "---\ntracker: [unterminated\n---\nBroken prompt\n")

    failed_output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:profile_reload, [
                   "--json",
                   @guardrails_ack,
                   "--workflow",
                   workflow_path,
                   "--env",
                   "LINEAR_API_KEY=#{@secret}",
                   "--profile-cache",
                   cache_path,
                   "--trace-id",
                   "trace:profile-reload-failed"
                 ])
      end)

    failed = Jason.decode!(failed_output)

    assert failed["ok"] == true
    assert failed["data"]["status"] == "reload_failed"
    assert failed["data"]["error"]["code"] == "workflow_parse_error"
    assert failed["data"]["last_known_good"]["workflow"]["path"] == "[redacted-path]"

    status_output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:status, [
                   "--json",
                   "--profile-cache",
                   cache_path,
                   "--trace-id",
                   "trace:profile-status"
                 ])
      end)

    status = Jason.decode!(status_output)
    workflow_reload = get_in(status, ["data", "data", "metadata", "workflow_reload"])

    assert workflow_reload["status"] == "reload_failed"
    assert workflow_reload["error"]["code"] == "workflow_parse_error"
    assert workflow_reload["last_known_good"]["status"] == "available"
    assert workflow_reload["last_known_good"]["workflow_path"] == "[redacted-path]"

    assert workflow_reload["last_known_good"]["prompt_hash"] ==
             initial["data"]["profile"]["workflow"]["prompt_hash"]

    refute initial_output =~ @secret
    refute failed_output =~ @secret
    refute status_output =~ @secret
  end

  test "status and logs commands read through AppKit runtime surface" do
    for {operation, schema_ref} <- [
          {:status, "headless_runtime_status.v1"},
          {:logs, "headless_runtime_logs.v1"}
        ] do
      output =
        capture_io(fn ->
          assert :ok = HeadlessCLI.run(operation, ["--json", "--trace-id", "trace:runtime"])
        end)

      decoded = Jason.decode!(output)

      assert decoded["ok"] == true
      assert decoded["operation"] == Atom.to_string(operation)
      assert decoded["data"]["schema_ref"] == schema_ref

      case operation do
        :status ->
          assert decoded["data"]["data"]["tenant_ref"] == "extravaganza"
          cleanup = decoded["data"]["data"]["health"]["startup_terminal_cleanup"]
          assert cleanup["last_cleanup_at"] == "2026-05-13T00:29:00Z"
          assert cleanup["candidate_count"] == 3
          assert cleanup["cleaned_count"] == 2
          assert cleanup["skipped_count"] == 0
          assert cleanup["failed_count"] == 1
          assert cleanup["attempt_count"] == 3

          assert cleanup["retained_workspace_refs"] == [
                   "workspace://terminal-failed"
                 ]

          assert cleanup["failures"] == [
                   %{
                     "workspace_ref" => "workspace://terminal-failed",
                     "reason" => "cleanup_denied"
                   }
                 ]

        :logs ->
          assert get_in(decoded, [
                   "data",
                   "data",
                   "entries",
                   Access.at(0),
                   "payload",
                   "tenant_ref"
                 ]) ==
                   "extravaganza"

          cleanup_log =
            Enum.find(
              decoded["data"]["data"]["entries"],
              &(&1["event_kind"] == "startup.terminal_cleanup.completed")
            )

          assert cleanup_log["payload"]["attempt_count"] == 3
          assert cleanup_log["payload"]["failed_count"] == 1

          assert cleanup_log["payload"]["retained_workspace_refs"] == [
                   "workspace://terminal-failed"
                 ]
      end
    end
  end

  @tag :tmp_dir
  test "logs command carries logs root and redacts structured operator entries", %{
    tmp_dir: tmp_dir
  } do
    logs_root = Path.join(tmp_dir, "operator-logs")

    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:logs, [
                   "--json",
                   "--logs-root",
                   logs_root,
                   "--trace-id",
                   "trace:runtime"
                 ])
      end)

    assert_received {:runtime_logs_request,
                     %{
                       "logs_root" => ^logs_root,
                       "trace_id" => "trace:runtime"
                     }}

    decoded = Jason.decode!(output)
    assert decoded["ok"] == true
    assert decoded["operation"] == "logs"
    assert decoded["data"]["schema_ref"] == "headless_runtime_logs.v1"
    assert decoded["data"]["data"]["metadata"]["logs_root"] == "[redacted-path]"

    session_log =
      Enum.find(
        decoded["data"]["data"]["entries"],
        &(&1["event_kind"] == "agent.session.event")
      )

    assert session_log["payload"]["issue_id"] == "ENG-42"
    assert session_log["payload"]["issue_identifier"] == "ENG-42"
    assert session_log["payload"]["session_id"] == "session:fixture"
    assert session_log["payload"]["trace_id"] == "trace:runtime"
    assert session_log["occurred_at"] == "2026-05-13T00:30:00Z"
    assert session_log["payload"]["credential_hint"] == "[redacted]"
    assert session_log["payload"]["workspace_hint"] == "[redacted-path]"
    refute Map.has_key?(session_log["payload"], "api_key")
    refute Map.has_key?(session_log["payload"], "workspace_path")
    refute output =~ @secret
    refute output =~ tmp_dir
  end

  test "source_publish command delegates to AppKit source surface" do
    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:source_publish, [
                   "--json",
                   @guardrails_ack,
                   "--subject",
                   "subject:fixture",
                   "--trace-id",
                   "trace:source-publish"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "source_publish"
    assert decoded["data"]["schema_ref"] == "headless_source_publication.v1"
    assert decoded["data"]["data"]["status"] == "receipt_recorded"
    assert decoded["refs"]["source_publication_ref"] == "source-publication:fixture"
  end

  test "HeadlessSurface exposes runtime status logs and source publication wrappers" do
    assert {:ok, status} = HeadlessSurface.runtime_status(%{}, [])
    assert status.health["runtime"] == "ok"
    assert status.health["startup_terminal_cleanup"]["last_cleanup_at"] == "2026-05-13T00:29:00Z"
    assert status.health["startup_terminal_cleanup"]["cleaned_count"] == 2

    assert {:ok, logs} = HeadlessSurface.runtime_logs(%{}, [])

    assert Enum.any?(logs.entries, &(&1.event_kind == "runtime_profile_applied"))
    assert Enum.any?(logs.entries, &(&1.event_kind == "startup.terminal_cleanup.completed"))

    assert {:ok, published} =
             HeadlessSurface.publish_linear_source(%{
               subject_ref: "subject:fixture",
               effect: "comment"
             })

    assert published["source_publication_receipt_ref"] == "source-publication:fixture"
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  defp write_workflow!(tmp_dir) do
    path = Path.join(tmp_dir, "WORKFLOW.md")

    File.write!(path, """
    ---
    tracker:
      kind: linear
      api_key: $LINEAR_API_KEY
      project_slug: ENG
    codex:
      command: codex app-server
    worker:
      ssh_hosts:
        - worker-a
      max_concurrent_agents_per_host: 2
    ---
    Ship {{ issue.identifier }}
    """)

    path
  end

  defp write_future_policy_workflow!(tmp_dir) do
    path = Path.join(tmp_dir, "WORKFLOW-future-policy.md")

    File.write!(path, """
    ---
    tracker:
      kind: linear
      api_key: $LINEAR_API_KEY
      project_slug: ENG
      active_states:
        - Ready
        - In Progress
      terminal_states:
        - Done
        - Canceled
    polling:
      interval_ms: 12345
    workspace:
      root: future-workspaces
    worker:
      ssh_hosts:
        - worker-a
      max_concurrent_agents_per_host: 1
    agent:
      max_concurrent_agents: 4
      max_turns: 8
      max_retry_backoff_ms: 44000
      max_concurrent_agents_by_state:
        Ready: 2
    codex:
      command: codex app-server --profile future
      approval_policy:
        reject:
          sandbox_approval: false
          rules: true
          mcp_elicitations: true
      thread_sandbox: danger-full-access
      turn_sandbox_policy:
        type: dangerFullAccess
      turn_timeout_ms: 60000
      read_timeout_ms: 7000
      stall_timeout_ms: 9000
    hooks:
      before_run: scripts/before_run.sh
      after_run: scripts/after_run.sh
      timeout_ms: 2500
    ---
    Ship {{ issue.identifier }}
    """)

    path
  end

  defmodule RuntimeBackend do
    @behaviour AppKit.Core.Backends.RuntimeBackend

    @impl true
    def apply_runtime_profile(context, runtime_profile, _opts) do
      RuntimeProfileApplyResult.new(%{
        status: :updated,
        tenant_ref: context.tenant_ref.id,
        profile_ref: "runtime-profile://symphony-workflow",
        program_ref: "program://#{get_in(runtime_profile, ["program", "slug"])}",
        policy_bundle_ref: "policy-bundle://symphony-workflow",
        work_class_ref: "work-class://symphony-workflow",
        placement_profile_ref: "placement-profile://symphony-workflow-local",
        metadata: %{"source" => "runtime-backend-test"}
      })
    end

    @impl true
    def runtime_status(context, _request, _opts) do
      RuntimeStatusSnapshot.new(%{
        tenant_ref: context.tenant_ref.id,
        program_ref: "program://symphony-workflow",
        health: %{
          "runtime" => "ok",
          "startup_terminal_cleanup" => %{
            "last_cleanup_at" => "2026-05-13T00:29:00Z",
            "candidate_count" => 3,
            "attempt_count" => 3,
            "cleaned_count" => 2,
            "skipped_count" => 0,
            "failed_count" => 1,
            "receipt_refs" => [
              "cleanup-receipt://T-100",
              "cleanup-receipt://T-101"
            ],
            "retained_workspace_refs" => [
              "workspace://terminal-failed"
            ],
            "failures" => [
              %{
                "workspace_ref" => "workspace://terminal-failed",
                "reason" => "cleanup_denied"
              }
            ]
          }
        },
        preflight: %{"linear" => "credential_present"},
        metadata: %{"source" => "runtime-backend-test"}
      })
    end

    @impl true
    def runtime_logs(context, request, _opts) do
      send(self(), {:runtime_logs_request, request})

      RuntimeLogPage.new(%{
        entries: [
          %{
            ref: "runtime-log:fixture:1",
            event_kind: "runtime_profile_applied",
            occurred_at: "2026-05-11T00:00:00Z",
            summary: "Runtime profile applied",
            payload: %{"tenant_ref" => context.tenant_ref.id}
          },
          %{
            ref: "runtime-log:fixture:2",
            event_kind: "startup.terminal_cleanup.completed",
            occurred_at: "2026-05-13T00:29:00Z",
            summary: "Startup terminal workspace cleanup completed with retained workspaces",
            payload: %{
              "tenant_ref" => context.tenant_ref.id,
              "attempt_count" => 3,
              "cleaned_count" => 2,
              "failed_count" => 1,
              "retained_workspace_refs" => ["workspace://terminal-failed"]
            }
          },
          %{
            ref: "runtime-log:fixture:3",
            event_kind: "agent.session.event",
            occurred_at: ~U[2026-05-13T00:30:00Z],
            summary: "Agent session emitted structured runtime log",
            payload: %{
              "tenant_ref" => context.tenant_ref.id,
              "issue_id" => "ENG-42",
              "issue_identifier" => "ENG-42",
              "session_id" => "session:fixture",
              "trace_id" => Map.get(request, "trace_id"),
              "credential_hint" => "linear-secret-value",
              "api_key" => "linear-secret-value",
              "workspace_hint" => "/tmp/extravaganza/ENG-42",
              "workspace_path" => "/tmp/extravaganza/ENG-42"
            }
          }
        ],
        total_count: 3,
        has_more?: false,
        metadata: %{"logs_root" => Map.get(request, "logs_root")}
      })
    end

    @impl true
    def record_live_effect(context, attrs, _opts) do
      LiveEffectReceipt.new(
        Map.merge(attrs, %{
          tenant_ref: context.tenant_ref.id,
          provider: "linear",
          effect: "comment",
          status: :receipt_recorded
        })
      )
    end
  end

  defmodule SourceBackend do
    @behaviour AppKit.Core.Backends.SourceBackend

    @impl true
    def sync_source(_context, source_role_ref, _source_page, _opts),
      do: {:ok, %{source_role_ref: source_role_ref}}

    @impl true
    def current_states(_context, source_role_ref, _request, _opts),
      do: {:ok, %{source_role_ref: source_role_ref}}

    @impl true
    def fetch_candidates(_context, source_role_ref, request, _opts) do
      source_binding = Map.fetch!(request, :source_binding)

      {:ok,
       %{
         source_role_ref: source_role_ref,
         source_binding_id: Map.get(source_binding, :source_binding_id) || "linear-primary",
         source_intake: %{operation: "linear.issues.list", subject_attrs: []},
         provider_request_sent?: true,
         provider_response_received?: true
       }}
    end

    @impl true
    def publish_source(context, _publication_role_ref, attrs, _opts) do
      {:ok,
       %{
         "source_publication_receipt_ref" => "source-publication:fixture",
         "tenant_ref" => context.tenant_ref.id,
         "subject_ref" => Map.get(attrs, :subject_ref) || Map.get(attrs, "subject_ref"),
         "status" => "receipt_recorded",
         "provider" => "linear",
         "effect" => Map.get(attrs, :effect) || Map.get(attrs, "effect") || "comment"
       }}
    end

    def invoke_runtime_tool(_context, _tool_role_ref, _operation_role_ref, _attrs, _opts) do
      {:ok,
       %{
         operation: "linear.graphql.execute",
         tool_name: "linear_graphql",
         success?: true,
         dynamic_tool_response: %{"success" => true, "output" => ~s({"data":{}})}
       }}
    end
  end
end
