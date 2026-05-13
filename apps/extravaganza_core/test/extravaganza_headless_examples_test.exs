defmodule Extravaganza.HeadlessExamplesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AppKit.Core.AgentIntake.RunOutcomeFuture

  alias AppKit.Core.RuntimeReadback.{
    RuntimeEventRow,
    RuntimeRow,
    RuntimeRunDetail
  }

  alias AppKit.Core.RuntimeSurface.GitHubPrEvidenceReceipt

  alias Extravaganza.{HeadlessCLI, HeadlessFixtureBackend}
  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  setup do
    previous_backend = Application.get_env(:app_kit_core, :headless_backend)
    previous_agent_intake_backend = Application.get_env(:app_kit_core, :agent_intake_backend)
    previous_runtime_backend = Application.get_env(:app_kit_core, :runtime_backend)
    previous_source_backend = Application.get_env(:app_kit_core, :source_backend)
    previous_fixture_context = Application.get_env(:extravaganza_core, :headless_fixture_context?)
    Process.put(:headless_examples_test_pid, self())
    Application.put_env(:app_kit_core, :headless_backend, HeadlessFixtureBackend)
    Application.put_env(:app_kit_core, :source_backend, __MODULE__.SourceBackend)
    Application.put_env(:extravaganza_core, :headless_fixture_context?, true)

    on_exit(fn ->
      Process.delete(:headless_examples_test_pid)
      Process.delete(:headless_examples_source_response)

      if previous_backend do
        Application.put_env(:app_kit_core, :headless_backend, previous_backend)
      else
        Application.delete_env(:app_kit_core, :headless_backend)
      end

      if previous_agent_intake_backend do
        Application.put_env(:app_kit_core, :agent_intake_backend, previous_agent_intake_backend)
      else
        Application.delete_env(:app_kit_core, :agent_intake_backend)
      end

      if previous_source_backend do
        Application.put_env(:app_kit_core, :source_backend, previous_source_backend)
      else
        Application.delete_env(:app_kit_core, :source_backend)
      end

      if previous_runtime_backend do
        Application.put_env(:app_kit_core, :runtime_backend, previous_runtime_backend)
      else
        Application.delete_env(:app_kit_core, :runtime_backend)
      end

      if is_nil(previous_fixture_context) do
        Application.delete_env(:extravaganza_core, :headless_fixture_context?)
      else
        Application.put_env(
          :extravaganza_core,
          :headless_fixture_context?,
          previous_fixture_context
        )
      end
    end)
  end

  test "headless CLI exposes all MVP operations" do
    assert HeadlessCLI.operations() == [
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
             :live_smoke,
             :evidence,
             :events,
             :smoke
           ]
  end

  test "documented logical Mix task aliases are loadable" do
    for task_module <- [
          Mix.Tasks.Extravaganza.Headless.SourceSync,
          Mix.Tasks.Extravaganza.Headless.SourcePublish,
          Mix.Tasks.Extravaganza.Headless.Status,
          Mix.Tasks.Extravaganza.Headless.Logs,
          Mix.Tasks.Extravaganza.Headless.LiveLinearSource,
          Mix.Tasks.Extravaganza.Headless.LiveLinearCurrentStates,
          Mix.Tasks.Extravaganza.Headless.LiveCodexTurn,
          Mix.Tasks.Extravaganza.Headless.LiveLinearPublication,
          Mix.Tasks.Extravaganza.Headless.LiveLinearGraphqlTool,
          Mix.Tasks.Extravaganza.Headless.LiveGithubEvidence,
          Mix.Tasks.Extravaganza.Headless.LiveSmoke
        ] do
      assert Code.ensure_loaded?(task_module)
    end
  end

  test "documented logical Mix task aliases dispatch to the same public operations" do
    for {task, operation, argv} <- [
          {"extravaganza.headless.source.sync", "source_sync", common_args()},
          {"extravaganza.headless.source_sync", "source_sync", common_args()},
          {"extravaganza.headless.live.linear_source", "live.linear-source",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live_linear_source", "live.linear-source",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live.linear_current_states", "live.linear-current-states",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live_linear_current_states", "live.linear-current-states",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live.codex_turn", "live.codex-turn",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live_codex_turn", "live.codex-turn",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live.linear_publication", "live.linear-publication",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live_linear_publication", "live.linear-publication",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live.linear_graphql_tool", "live.linear-graphql-tool",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live_linear_graphql_tool", "live.linear-graphql-tool",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live.github_evidence", "live.github-evidence",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live_github_evidence", "live.github-evidence",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live.smoke", "live.smoke",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live_smoke", "live.smoke",
           ["--json", "--trace-id", "trace:examples"]}
        ] do
      Mix.Task.reenable(task)

      output = capture_io(fn -> assert :ok = Mix.Task.run(task, argv) end)
      decoded = Jason.decode!(output)

      assert decoded["ok"] == true
      assert decoded["operation"] == operation
    end
  end

  test "task support keeps live provider product examples on the surface command path" do
    for operation <- [
          :live_linear_source,
          :live_linear_current_states,
          :live_codex_turn,
          :live_linear_publication,
          :live_linear_graphql_tool,
          :live_github_evidence,
          :live_smoke
        ] do
      refute TaskSupport.start_app?(
               operation,
               ["--json", "--live-product-path"]
             )
    end

    assert TaskSupport.start_app?(:state, ["--json"])
    refute TaskSupport.start_app?(:profile, ["--json"])

    refute TaskSupport.start_app?(:state, [
             "--fixture",
             "headless"
           ])
  end

  @tag :live_provider
  test "live provider examples skip explicitly without supplied credentials but exercise product path" do
    for {operation, expected_operation, provider, credential_refs} <- [
          {:live_linear_source, "live.linear-source", "linear", ["LINEAR_API_KEY"]},
          {:live_linear_current_states, "live.linear-current-states", "linear",
           ["LINEAR_API_KEY"]},
          {:live_codex_turn, "live.codex-turn", "codex", ["OPENAI_API_KEY", "CODEX_API_KEY"]},
          {:live_linear_publication, "live.linear-publication", "linear", ["LINEAR_API_KEY"]},
          {:live_linear_graphql_tool, "live.linear-graphql-tool", "linear", ["LINEAR_API_KEY"]},
          {:live_github_evidence, "live.github-evidence", "github", ["GH_TOKEN", "GITHUB_TOKEN"]}
        ] do
      output =
        capture_io(fn ->
          assert :ok = HeadlessCLI.run(operation, ["--json", "--trace-id", "trace:live"])
        end)

      decoded = Jason.decode!(output)

      assert decoded["ok"] == true
      assert decoded["operation"] == expected_operation
      assert decoded["data"]["status"] == "skipped"
      assert decoded["data"]["provider"] == provider
      assert decoded["data"]["credential_refs"] == credential_refs
      assert decoded["data"]["product_path_exercised?"] == true
      assert decoded["data"]["product_path"]["appkit_surfaces"] == ["AppKit.HeadlessSurface"]
      assert decoded["data"]["product_path"]["lower_path"] == []

      assert decoded["data"]["product_path"]["lower_path_status"] ==
               "skipped_before_live_provider_effect"

      assert decoded["data"]["provider_effect"]["skip_reason"]["code"] ==
               "credential_not_supplied_to_product_command"

      assert decoded["refs"]["run_ref"] == "run:fixture"
      refute Map.has_key?(decoded["refs"], "source_publication_ref")
      refute String.contains?(output, "env-linear")
      refute String.contains?(output, "env-github")
      refute String.contains?(output, "env-codex")
    end
  end

  @tag :live_provider
  test "linear api key stdin must be non-empty before it counts as supplied" do
    output =
      capture_io("", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_source, [
                   "--json",
                   "--api-key-stdin",
                   "--trace-id",
                   "trace:live-stdin"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == false
    assert decoded["operation"] == "live.linear-source"
    assert decoded["error"]["code"] == "credential_stdin_empty"
    refute output =~ "live_provider_effect_deferred"
  end

  @tag :live_provider
  test "linear source stdin executes the AppKit source path with redacted live-effect stages" do
    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_source, [
                   "--json",
                   "--api-key-stdin",
                   "--trace-id",
                   "trace:live-source"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "live.linear-source"
    assert decoded["data"]["status"] == "completed"
    assert decoded["data"]["provider_effect"]["status"] == "receipt_recorded"
    assert decoded["data"]["provider_effect"]["credential_present?"] == true
    assert decoded["data"]["provider_effect"]["provider_request_sent?"] == true
    assert decoded["data"]["provider_effect"]["provider_response_received?"] == true
    assert decoded["data"]["provider_effect"]["receipt_recorded?"] == true
    assert decoded["data"]["provider_effect"]["product_readback_confirmed?"] == true
    assert decoded["data"]["provider_effect"]["operation"] == "linear.issues.list"
    assert decoded["data"]["provider_effect"]["viewer_preflight?"] == true
    assert decoded["data"]["provider_effect"]["viewer_operation"] == "linear.users.get_self"
    assert decoded["data"]["provider_effect"]["viewer_provider_request_sent?"] == true
    assert decoded["data"]["provider_effect"]["viewer_provider_response_received?"] == true

    assert decoded["data"]["provider_effect"]["viewer_lower_request_ref"] =~
             "lower-request://linear/viewer"

    refute output =~ secret
    refute output =~ "live_provider_effect_deferred"

    assert_received {:fetch_linear_candidates, "extravaganza", source_binding, _opts}
    assert source_binding.source_binding_id == "linear-primary"
  end

  @tag :live_provider
  test "linear source product path accepts configured state filters and pagination" do
    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_source, [
                   "--json",
                   "--api-key-stdin",
                   "--source-state",
                   "Todo",
                   "--source-state",
                   "Backlog",
                   "--project-slug",
                   "ENG",
                   "--team-id",
                   "team-linear",
                   "--limit",
                   "7",
                   "--cursor",
                   "cursor-1",
                   "--trace-id",
                   "trace:live-source-states"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["data"]["status"] == "completed"
    assert decoded["data"]["provider_effect"]["source_state_names"] == ["Todo", "Backlog"]
    assert decoded["data"]["provider_effect"]["project_slug"] == "ENG"
    assert decoded["data"]["provider_effect"]["team_id"] == "team-linear"
    refute output =~ secret

    assert_received {:fetch_linear_candidates, "extravaganza", source_binding, opts}
    assert source_binding.candidate_filters.state_names == ["Todo", "Backlog"]
    assert source_binding.candidate_filters.project_slug == "ENG"
    assert source_binding.candidate_filters.team_id == "team-linear"
    assert Keyword.fetch!(opts, :first) == 7
    assert Keyword.fetch!(opts, :cursor) == "cursor-1"
    assert Keyword.fetch!(opts, :linear_api_key) == secret
  end

  @tag :live_provider
  test "linear source live product path passes stdin credential to AppKit without rendering it" do
    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_source, [
                   "--json",
                   "--api-key-stdin",
                   "--live-product-path",
                   "--trace-id",
                   "trace:live-source-product"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["data"]["status"] == "completed"
    assert_received {:fetch_linear_candidates, tenant_id, _source_binding, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert opts |> Keyword.fetch!(:pack_version) |> String.starts_with?("1.0.0-live.")
    assert Keyword.fetch!(opts, :linear_api_key) == secret
    refute output =~ secret
  end

  @tag :live_provider
  test "linear source product path can disable assignee-me routing explicitly" do
    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_source, [
                   "--json",
                   "--api-key-stdin",
                   "--assignee",
                   "all",
                   "--trace-id",
                   "trace:live-source-all-assignees"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["data"]["status"] == "completed"
    assert decoded["data"]["provider_effect"]["assignee"] == "all"

    assert_received {:fetch_linear_candidates, "extravaganza", source_binding, opts}
    refute Map.has_key?(source_binding.candidate_filters, :assignee)
    assert Keyword.fetch!(opts, :linear_api_key) == secret
    refute output =~ secret
  end

  @tag :live_provider
  test "linear source live product path does not require runtime repos for provider proof" do
    Application.delete_env(:extravaganza_core, :headless_fixture_context?)

    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_source, [
                   "--json",
                   "--api-key-stdin",
                   "--live-product-path",
                   "--trace-id",
                   "trace:live-source-surface-proof"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["data"]["status"] == "completed"
    assert decoded["data"]["product_path"]["proof_source"] == "fixture_headless_surface"
    assert decoded["data"]["provider_effect"]["provider_request_sent?"] == true
    refute output =~ secret
  end

  @tag :live_provider
  test "linear source live product path renders lower struct errors without leaking credentials" do
    secret = "linear-secret-value"

    Process.put(
      :headless_examples_source_response,
      {:error,
       %AppKit.Core.SurfaceError{
         code: "unsupported_runtime_profile_change",
         message: "Unsupported runtime profile change",
         kind: :validation,
         retryable: false,
         details: %{linear_api_key: secret}
       }}
    )

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_source, [
                   "--json",
                   "--api-key-stdin",
                   "--live-product-path",
                   "--trace-id",
                   "trace:live-source-error"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["data"]["status"] == "failed"
    assert decoded["data"]["provider_effect"]["error"] =~ "unsupported_runtime_profile_change"
    assert decoded["data"]["provider_effect"]["error"] =~ "[REDACTED]"
    refute output =~ secret
  end

  @tag :live_provider
  test "linear current-state live product path resolves issue states through AppKit" do
    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_current_states, [
                   "--json",
                   "--api-key-stdin",
                   "--live-product-path",
                   "--issue-ids",
                   "lin-issue-321,lin-missing",
                   "--trace-id",
                   "trace:live-current-states"
                 ])
      end)

    decoded = Jason.decode!(output)
    provider_effect = decoded["data"]["provider_effect"]

    assert decoded["ok"] == true
    assert decoded["operation"] == "live.linear-current-states"
    assert decoded["data"]["status"] == "completed"
    assert provider_effect["status"] == "receipt_recorded"
    assert provider_effect["operation"] == "linear.issues.list"
    assert provider_effect["credential_present?"] == true
    assert provider_effect["credential_redeemed?"] == true
    assert provider_effect["provider_request_sent?"] == true
    assert provider_effect["provider_response_received?"] == true
    assert provider_effect["receipt_recorded?"] == true
    assert provider_effect["requested_issue_ids"] == ["lin-issue-321", "lin-missing"]
    assert provider_effect["missing_issue_ids"] == ["lin-missing"]
    assert provider_effect["current_state_count"] == 1
    assert provider_effect["viewer_preflight?"] == true
    assert provider_effect["viewer_operation"] == "linear.users.get_self"
    assert provider_effect["viewer_provider_request_sent?"] == true
    assert provider_effect["viewer_provider_response_received?"] == true
    assert provider_effect["viewer_lower_request_ref"] =~ "lower-request://linear/viewer"
    assert provider_effect["lower_request_ref"] =~ "lower-request://linear/current-states"
    refute output =~ secret

    assert_received {:current_linear_issue_states, tenant_id, issue_ids, source_binding, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert issue_ids == ["lin-issue-321", "lin-missing"]
    assert source_binding.candidate_filters.assignee == "me"
    assert Keyword.fetch!(opts, :linear_api_key) == secret
    assert Keyword.fetch!(opts, :trace_id) == "trace:live-current-states"
  end

  @tag :live_provider
  test "codex turn live product path enters AgentIntake and confirms run-detail readback" do
    Application.put_env(:app_kit_core, :agent_intake_backend, __MODULE__.CodexAgentBackend)
    Application.put_env(:app_kit_core, :headless_backend, __MODULE__.CodexAgentBackend)

    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:live_codex_turn, [
                   "--json",
                   "--live-product-path",
                   "--trace-id",
                   "trace:live-codex-product"
                 ])
      end)

    decoded = Jason.decode!(output)
    data = decoded["data"]
    provider_effect = data["provider_effect"]

    assert decoded["ok"] == true
    assert decoded["operation"] == "live.codex-turn"
    assert data["status"] == "completed"

    assert data["product_path"]["appkit_surfaces"] == [
             "AppKit.AgentIntake",
             "AppKit.HeadlessSurface"
           ]

    assert provider_effect["status"] == "receipt_recorded"
    assert provider_effect["operation"] == "codex.session.turn"
    assert provider_effect["credential_present?"] == true
    assert provider_effect["credential_redeemed?"] == true
    assert provider_effect["provider_request_sent?"] == true
    assert provider_effect["provider_response_received?"] == true
    assert provider_effect["receipt_recorded?"] == true
    assert provider_effect["product_readback_confirmed?"] == true
    assert provider_effect["session_start_confirmed?"] == true
    assert provider_effect["session_ref"] == "session://codex/live-product"
    assert provider_effect["runtime_control_session_ref"] == "runtime-session://asm-live-product"
    assert provider_effect["session_start_event_kind"] == "codex.session.started"

    assert provider_effect["session_start_lower_receipt_ref"] ==
             "lower-receipt://codex/session-start/asm-live-product/started"

    assert provider_effect["app_server_protocol_confirmed?"] == true
    assert provider_effect["app_server_transport"] == "app_server"

    assert provider_effect["app_server_jsonrpc_methods"] == [
             "initialize",
             "initialized",
             "thread/start",
             "turn/start"
           ]

    assert provider_effect["app_server_initialization_confirmed?"] == true
    assert provider_effect["app_server_thread_start_confirmed?"] == true
    assert provider_effect["app_server_turn_start_confirmed?"] == true
    assert provider_effect["app_server_cwd_validation_confirmed?"] == true
    assert provider_effect["app_server_lower_request_ref"] == "lower-request://codex/session-turn"

    assert provider_effect["app_server_lower_receipt_ref"] ==
             "lower-receipt://codex/session-turn/succeeded"

    assert provider_effect["provider_session_id"] == "codex-provider-thread-live-product"
    assert provider_effect["provider_turn_id"] == "codex-provider-turn-live-product"

    assert provider_effect["turn_ref"] == "turn://codex/live-product/1"
    assert provider_effect["lower_request_ref"] == "lower-request://codex/session-turn"
    assert provider_effect["lower_receipt_ref"] == "lower-receipt://codex/session-turn/succeeded"
    assert data["lower_request_ref"] == provider_effect["lower_request_ref"]
    assert data["lower_receipt_ref"] == provider_effect["lower_receipt_ref"]

    assert_received {:start_agent_run, tenant_id, request, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert request.initial_input_ref == "prompt://extravaganza/live-codex-turn"
    assert request.params.capability_id == "codex.session.turn"
    assert request.params.provider_family == "codex"
    assert Keyword.fetch!(opts, :trace_id) == "trace:live-codex-product"

    assert_received {:runtime_run_detail, "run://codex/live-product", readback_request, _opts}
    assert readback_request.capability_id == "codex.session.turn"
    refute output =~ "env-codex"
    refute output =~ "live_provider_effect_deferred"
  end

  @tag :live_provider
  test "github evidence live product path fetches provider evidence through AppKit without writes" do
    Application.put_env(:app_kit_core, :runtime_backend, __MODULE__.GitHubEvidenceBackend)

    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:live_github_evidence, [
                   "--json",
                   "--live-product-path",
                   "--repo",
                   "nshkrdotcom/extravaganza",
                   "--pull-number",
                   "17",
                   "--ref",
                   "head-sha",
                   "--trace-id",
                   "trace:live-github-product"
                 ])
      end)

    decoded = Jason.decode!(output)
    data = decoded["data"]
    provider_effect = data["provider_effect"]

    assert decoded["ok"] == true
    assert decoded["operation"] == "live.github-evidence"
    assert data["status"] == "completed"

    assert data["product_path"]["appkit_surfaces"] == [
             "AppKit.RuntimeSurface",
             "AppKit.HeadlessSurface"
           ]

    assert provider_effect["status"] == "receipt_recorded"
    assert provider_effect["operation"] == "github.pr.evidence"
    assert provider_effect["credential_present?"] == true
    assert provider_effect["credential_redeemed?"] == true
    assert provider_effect["provider_request_sent?"] == true
    assert provider_effect["provider_response_received?"] == true
    assert provider_effect["receipt_recorded?"] == true
    assert provider_effect["product_readback_confirmed?"] == true
    assert provider_effect["repo"] == "nshkrdotcom/extravaganza"
    assert provider_effect["pull_number"] == 17
    assert provider_effect["head_sha"] == "head-sha"
    assert provider_effect["provider_ids"]["pull_request"] == "17"
    assert provider_effect["provider_ids"]["reviews"] == ["1", "2"]
    assert provider_effect["provider_ids"]["review_comments"] == ["11"]
    assert provider_effect["provider_ids"]["check_runs"] == ["100"]
    assert provider_effect["provider_refs"]["pull_request"] =~ "/pull/17"
    assert provider_effect["write_operations"] == []
    assert provider_effect["fixture_setup_required?"] == false
    assert data["lower_request_ref"] == "lower-request://github/pr-fetch"
    assert data["lower_receipt_ref"] == "lower-receipt://github/pr-fetch/succeeded"
    assert data["connector_manifest_ref"] == "manifest://jido/connectors/github@test"
    assert data["capability_negotiation_ref"] == "cap-neg://github/pr-fetch"
    refute Map.has_key?(data, "source_publication_ref")

    assert_received {:fetch_github_pr_evidence, tenant_id, request, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert request.repo == "nshkrdotcom/extravaganza"
    assert request.pull_number == 17
    assert request.ref == "head-sha"
    assert Keyword.fetch!(opts, :trace_id) == "trace:live-github-product"
    refute output =~ "env-github"
    refute output =~ "live_provider_effect_deferred"
  end

  @tag :live_provider
  test "aggregate live smoke product path completes only with all provider effects on one trace" do
    Application.put_env(:app_kit_core, :agent_intake_backend, __MODULE__.CodexAgentBackend)
    Application.put_env(:app_kit_core, :headless_backend, __MODULE__.CodexAgentBackend)
    Application.put_env(:app_kit_core, :runtime_backend, __MODULE__.GitHubEvidenceBackend)

    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_smoke, [
                   "--json",
                   "--api-key-stdin",
                   "--live-product-path",
                   "--repo",
                   "nshkrdotcom/extravaganza",
                   "--pull-number",
                   "17",
                   "--ref",
                   "head-sha",
                   "--trace-id",
                   "trace:live-smoke-product"
                 ])
      end)

    decoded = Jason.decode!(output)
    data = decoded["data"]
    examples = data["examples"]

    assert decoded["ok"] == true
    assert decoded["operation"] == "live.smoke"
    assert data["status"] == "completed"
    assert data["trace_id"] == "trace:live-smoke-product"
    assert data["correlation_ref"] == "live-smoke://trace-live-smoke-product"
    assert data["all_provider_effects_completed?"] == true
    assert data["product_readback_confirmed?"] == true

    assert data["completed_operations"] |> Enum.sort() == [
             "live.codex-turn",
             "live.github-evidence",
             "live.linear-current-states",
             "live.linear-graphql-tool",
             "live.linear-publication",
             "live.linear-source"
           ]

    assert data["skipped_operations"] == []
    assert data["failed_operations"] == []

    assert data["source_publication_ref"] ==
             examples["live.linear-publication"]["source_publication_ref"]

    for operation <- data["completed_operations"] do
      assert examples[operation]["status"] == "completed"
      assert examples[operation]["trace_id"] == "trace:live-smoke-product"
      assert examples[operation]["provider_effect"]["status"] == "receipt_recorded"
      assert examples[operation]["provider_effect"]["provider_request_sent?"] == true
      assert examples[operation]["provider_effect"]["provider_response_received?"] == true
      assert examples[operation]["provider_effect"]["receipt_recorded?"] == true
      assert examples[operation]["provider_effect"]["product_readback_confirmed?"] == true
    end

    assert examples["live.github-evidence"]["provider_effect"]["write_operations"] == []
    refute output =~ secret
    refute output =~ "live_provider_effect_deferred"

    assert_received {:fetch_linear_candidates, tenant_id, _source_binding, source_opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert Keyword.fetch!(source_opts, :trace_id) == "trace:live-smoke-product"
    assert Keyword.fetch!(source_opts, :linear_api_key) == secret

    assert_received {:current_linear_issue_states, _tenant_id, ["lin-issue-321"],
                     current_source_binding, current_opts}

    assert current_source_binding.candidate_filters.assignee == "me"
    assert Keyword.fetch!(current_opts, :trace_id) == "trace:live-smoke-product"
    assert Keyword.fetch!(current_opts, :linear_api_key) == secret

    assert_received {:start_agent_run, _tenant_id, request, codex_opts}
    assert request.trace_id == "trace:live-smoke-product"
    assert Keyword.fetch!(codex_opts, :trace_id) == "trace:live-smoke-product"

    assert_received {:runtime_run_detail, "run://codex/live-product", _readback_request,
                     codex_readback_opts}

    assert Keyword.fetch!(codex_readback_opts, :trace_id) == "trace:live-smoke-product"

    assert_received {:publish_linear_source, _tenant_id, attrs, publication_opts}
    assert attrs.issue_id == "lin-issue-321"
    assert Keyword.fetch!(publication_opts, :trace_id) == "trace:live-smoke-product"
    assert Keyword.fetch!(publication_opts, :linear_api_key) == secret

    assert_received {:execute_linear_graphql_tool, _tenant_id, graphql_attrs, graphql_opts}
    assert graphql_attrs.query == "query Viewer { viewer { id } }"
    assert Keyword.fetch!(graphql_opts, :trace_id) == "trace:live-smoke-product"
    assert Keyword.fetch!(graphql_opts, :linear_api_key) == secret

    assert_received {:fetch_github_pr_evidence, _tenant_id, github_request, github_opts}
    assert github_request.repo == "nshkrdotcom/extravaganza"
    assert github_request.pull_number == 17
    assert github_request.ref == "head-sha"
    assert Keyword.fetch!(github_opts, :trace_id) == "trace:live-smoke-product"
  end

  @tag :live_provider
  test "linear source stdin default fixture path installs the product fixture source backend" do
    Application.delete_env(:app_kit_core, :source_backend)
    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_source, [
                   "--json",
                   "--api-key-stdin",
                   "--trace-id",
                   "trace:live-source-fixture"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["data"]["status"] == "completed"
    assert decoded["data"]["provider_effect"]["operation"] == "linear.issues.list"

    assert [
             %{
               "source_ref" => "linear://fixture/issue/ENG-321",
               "provider_external_ref" => "lin-issue-321",
               "title" => "Investigate rollback",
               "description" => "The deployment rolled back after the health checks failed.",
               "priority" => 2,
               "labels" => ["automation", "incident"],
               "branch_ref" => "eng-321-investigate-rollback",
               "source_url" => "https://linear.app/acme/issue/ENG-321",
               "source_state" => "Todo",
               "provider_revision" => "2026-03-12T10:00:00Z",
               "blocker_refs" => [
                 %{
                   "identifier" => "SEC-9",
                   "source_state" => "In Progress"
                 }
               ],
               "source_routing" => %{
                 "team" => %{"id" => "team-eng", "key" => "ENG"}
               }
             }
           ] = decoded["data"]["provider_effect"]["subjects"]

    assert decoded["data"]["product_path"]["appkit_surfaces"] == [
             "AppKit.SourceSurface",
             "AppKit.HeadlessSurface"
           ]

    refute output =~ secret
    refute output =~ "missing_authorized_source_invocation"
  end

  @tag :live_provider
  test "linear publication stdin executes the AppKit source publication path" do
    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_publication, [
                   "--json",
                   "--api-key-stdin",
                   "--trace-id",
                   "trace:live-publication"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "live.linear-publication"
    assert decoded["data"]["status"] == "completed"
    assert decoded["data"]["provider_effect"]["status"] == "receipt_recorded"
    assert decoded["data"]["provider_effect"]["operation"] == "linear.comments.create"
    assert decoded["data"]["provider_effect"]["credential_present?"] == true
    assert decoded["data"]["provider_effect"]["provider_request_sent?"] == true
    assert decoded["data"]["provider_effect"]["provider_response_received?"] == true
    assert decoded["refs"]["source_publication_ref"] == "source-publication://linear-primary/test"
    refute output =~ secret
    refute output =~ "live_provider_effect_deferred"

    assert_received {:fetch_linear_candidates, "extravaganza", source_binding, _source_opts}
    assert source_binding.source_binding_id == "linear-primary"

    assert_received {:publish_linear_source, "extravaganza", attrs, opts}
    assert attrs.source_binding_id == "linear-primary"
    assert attrs.issue_id == "lin-issue-321"
    assert Keyword.fetch!(opts, :linear_api_key) == secret
  end

  @tag :live_provider
  test "linear publication can update an existing comment through the product path" do
    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_publication, [
                   "--json",
                   "--api-key-stdin",
                   "--issue-id",
                   "lin-issue-321",
                   "--comment-id",
                   "comment-1",
                   "--message",
                   "Updated by product path",
                   "--trace-id",
                   "trace:live-publication-update"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["data"]["provider_effect"]["operation"] == "linear.comments.update"
    assert decoded["data"]["provider_effect"]["workpad_refs"] == ["linear-comment://comment-1"]
    refute output =~ secret

    assert_received {:publish_linear_source, "extravaganza", attrs, opts}
    assert attrs.comment_id == "comment-1"
    assert attrs.body == "Updated by product path"
    assert Keyword.fetch!(opts, :linear_api_key) == secret
  end

  @tag :live_provider
  test "linear publication reports update-to-create fallback through the product path" do
    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_publication, [
                   "--json",
                   "--api-key-stdin",
                   "--issue-id",
                   "lin-issue-321",
                   "--comment-id",
                   "stale-comment",
                   "--allow-create-fallback",
                   "--trace-id",
                   "trace:live-publication-fallback"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["data"]["provider_effect"]["operation"] == "linear.comments.create"
    assert decoded["data"]["provider_effect"]["fallback_from"] == "linear.comments.update"

    assert decoded["data"]["provider_effect"]["workpad_refs"] == [
             "linear-comment://comment-created"
           ]

    refute output =~ secret

    assert_received {:publish_linear_source, "extravaganza", attrs, _opts}
    assert attrs.comment_id == "stale-comment"
    assert attrs.allow_create_fallback? == true
  end

  @tag :live_provider
  test "linear publication can update issue state through the product path" do
    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_publication, [
                   "--json",
                   "--api-key-stdin",
                   "--issue-id",
                   "lin-issue-321",
                   "--state-name",
                   "Done",
                   "--team-id",
                   "team-linear",
                   "--trace-id",
                   "trace:live-publication-state"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["data"]["provider_effect"]["operation"] == "linear.issues.update"
    assert decoded["data"]["provider_effect"]["state_name"] == "Done"
    assert decoded["data"]["provider_effect"]["state_id"] == "state-done"
    assert "linear.issues.update" in decoded["data"]["provider_effect"]["capability_ids"]
    assert "linear.workflow_states.list" in decoded["data"]["provider_effect"]["capability_ids"]
    refute output =~ secret

    assert_received {:publish_linear_source, "extravaganza", attrs, opts}
    assert attrs.issue_id == "lin-issue-321"
    assert attrs.state_name == "Done"
    assert attrs.team_id == "team-linear"
    assert Keyword.fetch!(opts, :linear_api_key) == secret
  end

  @tag :live_provider
  test "linear publication dry-run reports a governed lower denial through the product path" do
    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_publication, [
                   "--json",
                   "--api-key-stdin",
                   "--issue-id",
                   "lin-issue-321",
                   "--dry-run",
                   "--trace-id",
                   "trace:live-publication-dry-run"
                 ])
      end)

    decoded = Jason.decode!(output)
    provider_effect = decoded["data"]["provider_effect"]

    assert decoded["ok"] == true
    assert decoded["data"]["status"] == "completed"
    assert provider_effect["status"] == "governed_denial_recorded"
    assert provider_effect["operation"] == "linear.comments.create"
    assert provider_effect["credential_present?"] == true
    assert provider_effect["credential_redeemed?"] == true
    assert provider_effect["provider_request_sent?"] == false
    assert provider_effect["provider_response_received?"] == false
    assert provider_effect["lower_denial_ref"] =~ "policy_denied"
    assert provider_effect["dry_run?"] == true
    refute Map.has_key?(decoded["refs"], "source_publication_ref")
    refute output =~ secret

    assert_received {:publish_linear_source, "extravaganza", attrs, opts}
    assert attrs.issue_id == "lin-issue-321"
    assert Keyword.fetch!(opts, :dry_run?) == true
    assert Keyword.fetch!(opts, :linear_api_key) == secret
  end

  @tag :live_provider
  test "linear GraphQL dynamic tool executes through the product AppKit path" do
    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_graphql_tool, [
                   "--json",
                   "--api-key-stdin",
                   "--live-product-path",
                   "--query",
                   "query Viewer { viewer { id } }",
                   "--variables-json",
                   ~s({"includeTeams":false}),
                   "--trace-id",
                   "trace:live-linear-graphql-tool"
                 ])
      end)

    decoded = Jason.decode!(output)
    provider_effect = decoded["data"]["provider_effect"]
    dynamic_response = provider_effect["dynamic_tool_response"]

    assert decoded["ok"] == true
    assert decoded["operation"] == "live.linear-graphql-tool"
    assert decoded["data"]["status"] == "completed"
    assert provider_effect["status"] == "receipt_recorded"
    assert provider_effect["operation"] == "linear.graphql.execute"
    assert provider_effect["tool_name"] == "linear_graphql"
    assert provider_effect["credential_present?"] == true
    assert provider_effect["credential_redeemed?"] == true
    assert provider_effect["provider_request_sent?"] == true
    assert provider_effect["provider_response_received?"] == true
    assert provider_effect["receipt_recorded?"] == true
    assert dynamic_response["success"] == true

    assert Jason.decode!(dynamic_response["output"]) == %{
             "data" => %{"viewer" => %{"id" => "usr-linear-viewer"}}
           }

    assert_received {:execute_linear_graphql_tool, tenant_id, attrs, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert attrs.query == "query Viewer { viewer { id } }"
    assert attrs.variables == %{"includeTeams" => false}
    assert Keyword.fetch!(opts, :linear_api_key) == secret
    assert Keyword.fetch!(opts, :trace_id) == "trace:live-linear-graphql-tool"
    refute output =~ secret
  end

  @tag :live_provider
  test "aggregate live smoke emits a receipt for all live-gated provider examples" do
    output =
      capture_io(fn ->
        assert :ok = HeadlessCLI.run(:live_smoke, ["--json", "--trace-id", "trace:live"])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "live.smoke"
    assert decoded["data"]["status"] == "skipped"
    assert decoded["data"]["receipt_state"] == "recorded"
    assert decoded["data"]["product_path_exercised?"] == true
    assert decoded["data"]["product_path"]["entrypoint"] == "Extravaganza.ProductHost.live_smoke"

    assert decoded["data"]["examples"] |> Map.keys() |> Enum.sort() == [
             "live.codex-turn",
             "live.github-evidence",
             "live.linear-current-states",
             "live.linear-graphql-tool",
             "live.linear-publication",
             "live.linear-source"
           ]

    memory_matrix = decoded["data"]["deterministic_memory_tracker_matrix"]

    assert memory_matrix["proof_source"] == "fixture_memory_tracker"
    assert memory_matrix["live_provider_effect?"] == false
    assert memory_matrix["all_operations_covered?"] == true

    assert Enum.map(memory_matrix["operations"], & &1["symphony_callback"]) == [
             "fetch_candidate_issues",
             "fetch_issues_by_states",
             "fetch_issue_states_by_ids",
             "create_comment",
             "update_issue_state"
           ]

    assert Enum.all?(
             memory_matrix["operations"],
             &(&1["appkit_surface"] == "AppKit.SourceSurface")
           )

    assert Enum.all?(memory_matrix["operations"], &(&1["status"] == "fixture_receipt_recorded"))

    assert Enum.all?(
             memory_matrix["operations"],
             &(String.starts_with?(&1["lower_request_ref"], "lower-request://fixture/linear/") and
                 String.starts_with?(&1["lower_receipt_ref"], "lower-receipt://fixture/linear/"))
           )

    refute String.contains?(output, "env-linear")
    refute String.contains?(output, "env-github")
    refute String.contains?(output, "env-codex")
  end

  @tag :live_provider
  test "live command defaults to fixture-backed skip path without app runtime boot" do
    Application.delete_env(:app_kit_core, :headless_backend)
    Application.delete_env(:extravaganza_core, :headless_fixture_context?)

    output =
      capture_io(fn ->
        assert :ok = HeadlessCLI.run(:live_smoke, ["--json", "--trace-id", "trace:live"])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "live.smoke"
    assert decoded["data"]["status"] == "skipped"
    assert decoded["data"]["product_path"]["proof_source"] == "fixture_headless_surface"

    assert decoded["data"]["product_path"]["lower_path_status"] ==
             "skipped_before_live_provider_effect"

    assert decoded["refs"]["run_ref"] == "run:fixture"
  end

  test "CLI emits stable JSON envelopes for fixture state, run, evidence, and events" do
    for {operation, argv} <- [
          {:state, common_args()},
          {:run, ["run:fixture" | common_args()]},
          {:evidence, ["run:fixture" | common_args()]},
          {:events, ["--run", "run:fixture" | common_args()]}
        ] do
      output = capture_io(fn -> assert :ok = HeadlessCLI.run(operation, argv) end)
      decoded = Jason.decode!(output)

      assert decoded["ok"] == true
      assert decoded["schema"] == "extravaganza.headless.response.v1"
      assert decoded["operation"] == Atom.to_string(operation)
      assert decoded["trace_id"] == "trace:examples"
      refute String.contains?(output, "workspace_path")
      refute String.contains?(output, "/home/")
    end
  end

  test "golden headless examples are valid standard envelopes" do
    for path <- Path.wildcard("examples/headless/*.json") do
      body = path |> File.read!() |> Jason.decode!()

      assert body["ok"] in [true, false]

      assert body["schema"] in [
               "extravaganza.headless.response.v1",
               "extravaganza.headless.error.v1"
             ]

      assert is_binary(body["operation"])
    end
  end

  test "headless example scripts exist for the documented local operator path" do
    root = Path.expand("../../..", __DIR__)

    for path <- [
          "scripts/headless/state.exs",
          "scripts/headless/start_fixture_run.exs",
          "scripts/headless/assert_non_fixture_start.exs",
          "scripts/headless/run_detail.exs",
          "scripts/headless/review_decision.exs",
          "scripts/headless/evidence_chain.exs",
          "scripts/headless/source_sync.exs",
          "scripts/headless/source_publish.exs",
          "scripts/headless/status.exs",
          "scripts/headless/logs.exs",
          "scripts/headless/profile_validate.exs",
          "scripts/headless/profile_reload.exs",
          "scripts/headless/live_linear_source.exs",
          "scripts/headless/live_linear_current_states.exs",
          "scripts/headless/live_codex_turn.exs",
          "scripts/headless/live_linear_publication.exs",
          "scripts/headless/live_linear_graphql_tool.exs",
          "scripts/headless/live_github_evidence.exs",
          "scripts/headless/live_smoke.exs"
        ] do
      assert File.regular?(Path.join(root, path))
    end
  end

  defp common_args,
    do: ["--json", "--fixture", "headless_m1", "--trace-id", "trace:examples"]

  defmodule CodexAgentBackend do
    @behaviour AppKit.Core.Backends.AgentIntakeBackend
    @behaviour AppKit.Core.Backends.HeadlessBackend

    @run_ref "run://codex/live-product"
    @workflow_ref "workflow://codex/live-product"
    @session_ref "session://codex/live-product"
    @turn_ref "turn://codex/live-product/1"
    @lower_request_ref "lower-request://codex/session-turn"
    @lower_receipt_ref "lower-receipt://codex/session-turn/succeeded"
    @runtime_control_session_ref "runtime-session://asm-live-product"
    @session_start_lower_request_ref "lower-request://codex/session-start"
    @session_start_lower_receipt_ref "lower-receipt://codex/session-start/asm-live-product/started"
    @provider_session_id "codex-provider-thread-live-product"
    @provider_turn_id "codex-provider-turn-live-product"
    @app_server_jsonrpc_methods ["initialize", "initialized", "thread/start", "turn/start"]
    @observed_at ~U[2026-05-12 00:00:00Z]

    @impl true
    def start_agent_run(context, request, opts) do
      if pid = Process.get(:headless_examples_test_pid) do
        send(pid, {:start_agent_run, context.tenant_ref.id, request, opts})
      end

      RunOutcomeFuture.new(%{
        run_ref: @run_ref,
        workflow_ref: @workflow_ref,
        accepted?: true,
        command_ref: "command://#{request.idempotency_key}",
        correlation_id: request.correlation_id
      })
    end

    @impl true
    def submit_agent_turn(_context, _turn_submission, _opts), do: {:error, :not_used}

    @impl true
    def cancel_agent_run(_context, _run_ref, _opts), do: {:error, :not_used}

    @impl true
    def await_agent_outcome(_context, _run_ref, _request, _opts), do: {:error, :not_used}

    @impl true
    def state_snapshot(_context, _request, _opts), do: {:error, :not_used}

    @impl true
    def runtime_subject_detail(_context, _subject_ref, _request, _opts), do: {:error, :not_used}

    @impl true
    def runtime_run_detail(_context, run_ref, request, opts) do
      if pid = Process.get(:headless_examples_test_pid) do
        send(pid, {:runtime_run_detail, run_ref, request, opts})
      end

      with {:ok, runtime_row} <-
             RuntimeRow.new(%{
               subject_ref: "subject://extravaganza/live-codex-turn",
               run_ref: run_ref,
               workflow_ref: @workflow_ref,
               state: "completed",
               updated_at: @observed_at,
               provider_refs: %{"codex" => "provider-ref://codex/live-product"},
               extensions: %{
                 "codex_app_server_session_start" => %{
                   "confirmed?" => true,
                   "operation" => "codex.session.start",
                   "lifecycle" => "started",
                   "runtime_control_session_ref" => @runtime_control_session_ref,
                   "lower_request_ref" => @session_start_lower_request_ref,
                   "lower_receipt_ref" => @session_start_lower_receipt_ref
                 },
                 "codex_app_server_protocol" => %{
                   "confirmed?" => true,
                   "transport" => "app_server",
                   "jsonrpc_methods" => @app_server_jsonrpc_methods,
                   "initialization_confirmed?" => true,
                   "thread_start_confirmed?" => true,
                   "turn_start_confirmed?" => true,
                   "cwd_validation_confirmed?" => true,
                   "command_launch_owner" => "lower_runtime",
                   "timeout_policy_owner" => "lower_runtime",
                   "provider_session_id" => @provider_session_id,
                   "provider_turn_id" => @provider_turn_id,
                   "runtime_control_session_ref" => @runtime_control_session_ref,
                   "lower_request_ref" => @lower_request_ref,
                   "lower_receipt_ref" => @lower_receipt_ref
                 },
                 "source_publication" => %{
                   "status" => "not_applicable",
                   "capability_id" => "codex.session.turn"
                 }
               }
             }),
           {:ok, session_start_event} <-
             RuntimeEventRow.new(%{
               event_ref: "event://codex/live-product/session-start",
               event_seq: 1,
               event_kind: "codex.session.started",
               observed_at: @observed_at,
               subject_ref: "subject://extravaganza/live-codex-turn",
               run_ref: run_ref,
               workflow_ref: @workflow_ref,
               session_ref: @runtime_control_session_ref,
               turn_ref: @turn_ref,
               payload_ref: "payload://codex/live-product/session-start",
               extensions: %{
                 "lower_request_ref" => @session_start_lower_request_ref,
                 "lower_receipt_ref" => @session_start_lower_receipt_ref
               }
             }),
           {:ok, app_server_protocol_event} <-
             RuntimeEventRow.new(%{
               event_ref: "event://codex/live-product/app-server-protocol",
               event_seq: 2,
               event_kind: "codex.app_server.protocol.confirmed",
               observed_at: @observed_at,
               subject_ref: "subject://extravaganza/live-codex-turn",
               run_ref: run_ref,
               workflow_ref: @workflow_ref,
               session_ref: @runtime_control_session_ref,
               turn_ref: @turn_ref,
               payload_ref: "payload://codex/live-product/app-server-protocol",
               extensions: %{
                 "jsonrpc_methods" => @app_server_jsonrpc_methods,
                 "transport" => "app_server",
                 "lower_request_ref" => @lower_request_ref,
                 "lower_receipt_ref" => @lower_receipt_ref,
                 "provider_session_id" => @provider_session_id,
                 "provider_turn_id" => @provider_turn_id,
                 "cwd_validation_confirmed?" => true
               }
             }),
           {:ok, event} <-
             RuntimeEventRow.new(%{
               event_ref: "event://codex/live-product/terminal",
               event_seq: 3,
               event_kind: "run.terminal",
               observed_at: @observed_at,
               subject_ref: "subject://extravaganza/live-codex-turn",
               run_ref: run_ref,
               workflow_ref: @workflow_ref,
               turn_ref: @turn_ref,
               payload_ref: "payload://codex/live-product/terminal"
             }) do
        RuntimeRunDetail.new(%{
          run_ref: run_ref,
          runtime_row: runtime_row,
          events: [session_start_event, app_server_protocol_event, event],
          turns: [
            %{
              "turn_ref" => @turn_ref,
              "status" => "completed",
              "session_ref" => @session_ref,
              "operation" => "codex.session.turn",
              "credential_redeemed?" => true,
              "provider_request_sent?" => true,
              "provider_response_received?" => true,
              "session_start_confirmed?" => true,
              "runtime_control_session_ref" => @runtime_control_session_ref,
              "session_start_event_kind" => "codex.session.started",
              "session_start_lower_request_ref" => @session_start_lower_request_ref,
              "session_start_lower_receipt_ref" => @session_start_lower_receipt_ref,
              "app_server_protocol_confirmed?" => true,
              "app_server_transport" => "app_server",
              "app_server_jsonrpc_methods" => @app_server_jsonrpc_methods,
              "app_server_initialization_confirmed?" => true,
              "app_server_thread_start_confirmed?" => true,
              "app_server_turn_start_confirmed?" => true,
              "app_server_cwd_validation_confirmed?" => true,
              "app_server_lower_request_ref" => @lower_request_ref,
              "app_server_lower_receipt_ref" => @lower_receipt_ref,
              "provider_session_id" => @provider_session_id,
              "provider_turn_id" => @provider_turn_id,
              "lower_request_ref" => @lower_request_ref,
              "lower_receipt_ref" => @lower_receipt_ref
            }
          ],
          candidate_fact_refs: [],
          memory_proof_refs: []
        })
      end
    end

    @impl true
    def request_runtime_refresh(_context, _request, _opts), do: {:error, :not_used}

    @impl true
    def request_runtime_control(_context, _request, _opts), do: {:error, :not_used}
  end

  defmodule GitHubEvidenceBackend do
    @behaviour AppKit.Core.Backends.RuntimeBackend

    @capability_ids [
      "github.pr.fetch",
      "github.pr.reviews.list",
      "github.pr.review_comments.list",
      "github.commit.statuses.get_combined",
      "github.check_runs.list_for_ref"
    ]

    @impl true
    def apply_runtime_profile(_context, _runtime_profile, _opts), do: {:error, :not_used}

    @impl true
    def runtime_status(_context, _request, _opts), do: {:error, :not_used}

    @impl true
    def runtime_logs(_context, _request, _opts), do: {:error, :not_used}

    @impl true
    def record_live_effect(_context, _attrs, _opts), do: {:error, :not_used}

    @impl true
    def fetch_github_pr_evidence(context, request, opts) do
      if pid = Process.get(:headless_examples_test_pid) do
        send(pid, {:fetch_github_pr_evidence, context.tenant_ref.id, request, opts})
      end

      GitHubPrEvidenceReceipt.new(%{
        effect_ref: "live-effect://github/pr-evidence/test",
        tenant_ref: context.tenant_ref.id,
        provider: "github",
        effect: "github_pr_evidence",
        status: :receipt_recorded,
        capability_ids: @capability_ids,
        repo: request.repo,
        pull_number: request.pull_number,
        head_sha: request.ref,
        evidence_ref: "evidence://github-pr/nshkrdotcom/extravaganza/17/test",
        credential_present?: true,
        credential_redeemed?: true,
        provider_request_sent?: true,
        provider_response_received?: true,
        receipt_recorded?: true,
        product_readback_confirmed?: true,
        fixture_setup_required?: false,
        write_operations: [],
        provider_ids: %{
          pull_request: "17",
          reviews: ["1", "2"],
          review_comments: ["11"],
          check_runs: ["100"],
          combined_status_ref: "head-sha"
        },
        provider_refs: %{
          pull_request: "https://github.com/nshkrdotcom/extravaganza/pull/17",
          content_ref: "github-pr://nshkrdotcom/extravaganza/17"
        },
        counts: %{
          review_count: 2,
          review_comment_count: 1,
          status_count: 1,
          check_run_count: 1
        },
        receipt_refs: %{
          lower_request_refs: [
            "lower-request://github/pr-fetch",
            "lower-request://github/reviews",
            "lower-request://github/review-comments",
            "lower-request://github/status",
            "lower-request://github/checks"
          ],
          lower_receipt_refs: [
            "lower-receipt://github/pr-fetch/succeeded",
            "lower-receipt://github/reviews/succeeded",
            "lower-receipt://github/review-comments/succeeded",
            "lower-receipt://github/status/succeeded",
            "lower-receipt://github/checks/succeeded"
          ],
          evidence_ref: "evidence://github-pr/nshkrdotcom/extravaganza/17/test"
        },
        operation_receipts: [
          %{
            capability_id: "github.pr.fetch",
            capability_negotiation_ref: "cap-neg://github/pr-fetch",
            connector_manifest_ref: "manifest://jido/connectors/github@test",
            lower_request_ref: "lower-request://github/pr-fetch",
            lower_receipt_ref: "lower-receipt://github/pr-fetch/succeeded"
          }
        ],
        metadata: %{"source" => "test"}
      })
    end
  end

  defmodule SourceBackend do
    @behaviour AppKit.Core.Backends.SourceBackend

    @impl true
    def sync_linear_issues(_context, _source_page, _opts), do: {:ok, %{}}

    @impl true
    def current_linear_issue_states(context, issue_ids, source_binding, opts) do
      if pid = Process.get(:headless_examples_test_pid) do
        send(
          pid,
          {:current_linear_issue_states, context.tenant_ref.id, issue_ids, source_binding, opts}
        )
      end

      {:ok,
       %{
         requested_issue_ids: issue_ids,
         credential_redeemed?: true,
         provider_request_sent?: true,
         provider_response_received?: true,
         lower_request_ref: "lower-request://linear/current-states",
         lower_receipt_ref: "lower-receipt://linear/current-states/succeeded",
         source_current_state: %{
           operation: "linear.issues.list",
           subject_attrs: [
             %{
               source_ref: "linear://installation/issue/ENG-321",
               provider_external_ref: "lin-issue-321",
               source_state: "Todo"
             }
           ],
           missing_issue_ids: Enum.reject(issue_ids, &(&1 == "lin-issue-321"))
         },
         viewer_resolution: %{
           output: %{user: %{id: "usr-linear-viewer"}},
           provider_request_sent?: true,
           provider_response_received?: true,
           lower_request_ref: "lower-request://linear/viewer",
           lower_receipt_ref: "lower-receipt://linear/viewer/succeeded"
         }
       }}
    end

    @impl true
    def fetch_linear_candidates(context, source_binding, opts) do
      if pid = Process.get(:headless_examples_test_pid) do
        send(pid, {:fetch_linear_candidates, context.tenant_ref.id, source_binding, opts})
      end

      if response = Process.get(:headless_examples_source_response) do
        response
      else
        default_fetch_linear_candidates(source_binding)
      end
    end

    defp default_fetch_linear_candidates(source_binding) do
      {:ok,
       %{
         source_binding_id: source_binding.source_binding_id,
         source_intake: %{
           operation: "linear.issues.list",
           subject_attrs: [
             %{
               source_ref: "linear://installation/issue/ENG-321",
               provider_external_ref: "lin-issue-321",
               title: "Investigate rollback"
             }
           ]
         },
         provider_request_sent?: true,
         provider_response_received?: true,
         credential_redeemed?: true,
         viewer_resolution: %{
           output: %{user: %{id: "usr-linear-viewer"}},
           provider_request_sent?: true,
           provider_response_received?: true,
           lower_request_ref: "lower-request://linear/viewer",
           lower_receipt_ref: "lower-receipt://linear/viewer/succeeded"
         },
         lower_request_ref: "lower-request://linear/source",
         lower_receipt_ref: "lower-receipt://linear/source"
       }}
    end

    @impl true
    def publish_linear_source(context, attrs, opts) do
      if pid = Process.get(:headless_examples_test_pid) do
        send(pid, {:publish_linear_source, context.tenant_ref.id, attrs, opts})
      end

      receipt =
        cond do
          Keyword.get(opts, :dry_run?) == true ->
            %{
              source_publication_denial_ref:
                "lower-denial://linear/publication-dry-run/policy_denied",
              source_publish_ref: attrs.source_publish_ref,
              source_binding_id: attrs.source_binding_id,
              source_ref: attrs.source_ref,
              status: "dry_run_denied",
              capability_id: "linear.comments.create",
              issue_id: attrs.issue_id,
              lower_request_ref: "lower-request://linear/publication-dry-run",
              lower_denial_ref: "lower-denial://linear/publication-dry-run/policy_denied",
              denial_class: "policy_denied",
              denial_reason: "dry run requested before provider dispatch",
              provider_request_sent?: false,
              provider_response_received?: false,
              workpad_refs: []
            }

          Map.get(attrs, :state_id) || Map.get(attrs, :state_name) ->
            %{
              source_publication_receipt_ref: "source-publication://linear-primary/state-update",
              source_publish_ref: attrs.source_publish_ref,
              source_binding_id: attrs.source_binding_id,
              source_ref: attrs.source_ref,
              status: "published",
              capability_id: "linear.issues.update",
              issue_id: attrs.issue_id,
              state_name: Map.get(attrs, :state_name),
              state_id: Map.get(attrs, :state_id) || "state-done",
              lower_request_ref: "lower-request://linear/state-update",
              lower_receipt_ref: "lower-receipt://linear/state-update",
              workpad_refs: []
            }

          Map.get(attrs, :comment_id) == "stale-comment" ->
            %{
              source_publication_receipt_ref: "source-publication://linear-primary/fallback",
              source_publish_ref: attrs.source_publish_ref,
              source_binding_id: attrs.source_binding_id,
              source_ref: attrs.source_ref,
              status: "published",
              capability_id: "linear.comments.create",
              fallback_from: "linear.comments.update",
              lower_request_ref: "lower-request://linear/publication-fallback",
              lower_receipt_ref: "lower-receipt://linear/publication-fallback",
              workpad_refs: ["linear-comment://comment-created"]
            }

          Map.get(attrs, :comment_id) ->
            %{
              source_publication_receipt_ref: "source-publication://linear-primary/update",
              source_publish_ref: attrs.source_publish_ref,
              source_binding_id: attrs.source_binding_id,
              source_ref: attrs.source_ref,
              status: "published",
              capability_id: "linear.comments.update",
              lower_request_ref: "lower-request://linear/publication-update",
              lower_receipt_ref: "lower-receipt://linear/publication-update",
              workpad_refs: ["linear-comment://#{attrs.comment_id}"]
            }

          true ->
            %{
              source_publication_receipt_ref: "source-publication://linear-primary/test",
              source_publish_ref: attrs.source_publish_ref,
              source_binding_id: attrs.source_binding_id,
              source_ref: attrs.source_ref,
              status: "published",
              capability_id: "linear.comments.create",
              lower_request_ref: "lower-request://linear/publication",
              lower_receipt_ref: "lower-receipt://linear/publication",
              workpad_refs: ["linear-comment://comment-1"]
            }
        end

      {:ok,
       %{
         source_publication_receipt: receipt,
         credential_redeemed?: true,
         provider_request_sent?: Keyword.get(opts, :dry_run?) != true,
         provider_response_received?: Keyword.get(opts, :dry_run?) != true,
         lower_denial_ref: Map.get(receipt, :lower_denial_ref)
       }}
    end

    @impl true
    def execute_linear_graphql_tool(context, attrs, opts) do
      if pid = Process.get(:headless_examples_test_pid) do
        send(pid, {:execute_linear_graphql_tool, context.tenant_ref.id, attrs, opts})
      end

      output = ~s({"data":{"viewer":{"id":"usr-linear-viewer"}}})

      {:ok,
       %{
         operation: "linear.graphql.execute",
         tool_name: "linear_graphql",
         success?: true,
         dynamic_tool_response: %{
           "success" => true,
           "output" => output,
           "contentItems" => [
             %{
               "type" => "inputText",
               "text" => output
             }
           ]
         },
         lower_request_ref: "lower-request://linear/graphql",
         lower_receipt_ref: "lower-receipt://linear/graphql/succeeded",
         provider_request_sent?: true,
         provider_response_received?: true,
         credential_redeemed?: true
       }}
    end
  end
end
