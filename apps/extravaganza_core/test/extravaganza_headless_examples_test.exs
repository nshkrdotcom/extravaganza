defmodule Extravaganza.HeadlessExamplesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AppKit.Core.AgentIntake.RunOutcomeFuture

  alias AppKit.Core.RuntimeReadback.{
    RuntimeEventRow,
    RuntimeRow,
    RuntimeRunDetail
  }

  alias Extravaganza.{GitHubPrBranchCleanupReceipt, GitHubPrEvidenceReceipt}

  alias Extravaganza.{HeadlessCLI, HeadlessFixtureBackend}
  alias Mix.Tasks.Extravaganza.Headless.TaskSupport

  @guardrails_ack "--ack-headless-guardrails"
  @legacy_guardrails_ack "--i-understand-that-this-will-be-running-without-the-usual-guardrails"

  setup do
    previous_backend = Application.get_env(:app_kit_core, :headless_backend)
    previous_generic_backend = Application.get_env(:app_kit_core, :generic_backend)
    previous_runtime_backend = Application.get_env(:app_kit_core, :runtime_backend)
    previous_source_backend = Application.get_env(:app_kit_core, :source_backend)
    previous_fixture_context = Application.get_env(:extravaganza_core, :headless_fixture_context?)
    Process.put(:headless_examples_test_pid, self())
    Application.put_env(:app_kit_core, :headless_backend, HeadlessFixtureBackend)
    Application.put_env(:app_kit_core, :generic_backend, __MODULE__.GenericRuntimeBackend)
    Application.put_env(:app_kit_core, :source_backend, __MODULE__.SourceBackend)
    Application.put_env(:extravaganza_core, :headless_fixture_context?, true)

    on_exit(fn ->
      Process.delete(:headless_examples_test_pid)
      Process.delete(:codex_agent_prompt_readback)
      Process.delete(:codex_agent_continuation_readback)
      Process.delete(:headless_examples_source_response)

      if previous_backend do
        Application.put_env(:app_kit_core, :headless_backend, previous_backend)
      else
        Application.delete_env(:app_kit_core, :headless_backend)
      end

      if previous_generic_backend do
        Application.put_env(:app_kit_core, :generic_backend, previous_generic_backend)
      else
        Application.delete_env(:app_kit_core, :generic_backend)
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
             :preflight,
             :stop,
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
  end

  test "documented logical Mix task aliases are loadable" do
    for task_module <- [
          Mix.Tasks.Extravaganza.Headless.SourceSync,
          Mix.Tasks.Extravaganza.Headless.SourcePublish,
          Mix.Tasks.Extravaganza.Headless.Status,
          Mix.Tasks.Extravaganza.Headless.Logs,
          Mix.Tasks.Extravaganza.Headless.Preflight,
          Mix.Tasks.Extravaganza.Headless.Stop,
          Mix.Tasks.Extravaganza.Headless.LiveLinearSource,
          Mix.Tasks.Extravaganza.Headless.LiveLinearCurrentStates,
          Mix.Tasks.Extravaganza.Headless.LiveCodexTurn,
          Mix.Tasks.Extravaganza.Headless.LiveLinearPublication,
          Mix.Tasks.Extravaganza.Headless.LiveLinearGraphqlTool,
          Mix.Tasks.Extravaganza.Headless.LiveGithubEvidence,
          Mix.Tasks.Extravaganza.Headless.LiveGithubPrCleanup,
          Mix.Tasks.Extravaganza.Headless.LiveSmoke
        ] do
      assert Code.ensure_loaded?(task_module)
    end
  end

  test "documented logical Mix task aliases dispatch to the same public operations" do
    for {task, operation, argv} <- [
          {"extravaganza.headless.source.sync", "source_sync", common_args()},
          {"extravaganza.headless.source_sync", "source_sync", common_args()},
          {"extravaganza.headless.preflight", "preflight",
           [
             "--json",
             "--skip-app-start",
             "--temporal-status",
             "reachable",
             "--source-binding-ref",
             "linear_primary",
             "--credential-refs",
             "LINEAR_API_KEY,GH_TOKEN"
           ]},
          {"extravaganza.headless.stop", "stop",
           [
             "--json",
             "--fixture",
             "headless_m1",
             "--confirm-no-active-lower-runs",
             "--trace-id",
             "trace:examples"
           ]},
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
          {"extravaganza.headless.live.github_pr_cleanup", "live.github-pr-cleanup",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live_github_pr_cleanup", "live.github-pr-cleanup",
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
          :live_github_pr_cleanup,
          :live_smoke
        ] do
      refute TaskSupport.start_app?(
               operation,
               ["--json", "--live-product-path"]
             )
    end

    assert TaskSupport.start_app?(:state, ["--json"])
    refute TaskSupport.start_app?(:preflight, ["--json"])
    refute TaskSupport.start_app?(:stop, ["--json"])
    refute TaskSupport.start_app?(:profile, ["--json"])
    assert TaskSupport.guardrails_acknowledgement_pending?(:refresh, ["--json"])
    refute TaskSupport.start_app?(:refresh, ["--json"])

    refute TaskSupport.guardrails_acknowledgement_pending?(:refresh, [
             "--json",
             @guardrails_ack
           ])

    assert TaskSupport.start_app?(:refresh, ["--json", @guardrails_ack])

    assert TaskSupport.guardrails_acknowledgement_pending?(:live_codex_turn, [
             "--json",
             "--live-product-path"
           ])

    refute TaskSupport.guardrails_acknowledgement_pending?(:live_codex_turn, [
             "--json",
             @guardrails_ack,
             "--live-product-path"
           ])

    refute TaskSupport.start_app?(:state, [
             "--fixture",
             "headless"
           ])
  end

  @tag :live_provider
  test "live product paths require explicit operator acknowledgement" do
    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:live_codex_turn, [
                   "--json",
                   "--live-product-path",
                   "--trace-id",
                   "trace:live-ack-missing"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == false
    assert decoded["operation"] == "live.codex-turn"
    assert decoded["error"]["code"] == "operator_ack_required"

    assert decoded["error"]["details"]["required_flags"] == [
             @guardrails_ack,
             @legacy_guardrails_ack
           ]

    refute_received {:start_agent_run, _, _, _}

    Mix.Task.reenable("extravaganza.headless.live_codex_turn")

    task_output =
      capture_io(fn ->
        assert :ok =
                 Mix.Task.run("extravaganza.headless.live_codex_turn", [
                   "--json",
                   "--live-product-path",
                   "--trace-id",
                   "trace:live-task-ack-missing"
                 ])
      end)

    task_decoded = Jason.decode!(task_output)
    assert task_decoded["ok"] == false
    assert task_decoded["operation"] == "live.codex-turn"
    assert task_decoded["error"]["code"] == "operator_ack_required"

    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:live_codex_turn, [
                   "--json",
                   @guardrails_ack,
                   "--live-product-path",
                   "--trace-id",
                   "trace:live-ack-product"
                 ])
      end)

    decoded = Jason.decode!(output)
    assert decoded["ok"] == true
    assert decoded["data"]["status"] == "completed"
    assert decoded["data"]["provider_effect"]["status"] == "receipt_recorded"

    legacy_output =
      capture_io("linear-secret-value\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_source, [
                   "--json",
                   @legacy_guardrails_ack,
                   "--api-key-stdin",
                   "--live-product-path",
                   "--trace-id",
                   "trace:live-ack-legacy"
                 ])
      end)

    legacy_decoded = Jason.decode!(legacy_output)
    assert legacy_decoded["ok"] == true
    assert legacy_decoded["data"]["status"] == "completed"
    refute legacy_output =~ "linear-secret-value"
  end

  test "non-fixture mutating commands require explicit operator acknowledgement" do
    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:refresh, [
                   "--json",
                   "--trace-id",
                   "trace:refresh-ack-missing"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == false
    assert decoded["operation"] == "refresh"
    assert decoded["error"]["code"] == "operator_ack_required"

    accepted_output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:refresh, [
                   "--json",
                   @guardrails_ack,
                   "--trace-id",
                   "trace:refresh-ack-product"
                 ])
      end)

    accepted = Jason.decode!(accepted_output)
    assert accepted["ok"] == true
    assert get_in(accepted, ["data", "data", "status"]) == "accepted"

    fixture_output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:refresh, [
                   "--json",
                   "--fixture",
                   "headless",
                   "--trace-id",
                   "trace:refresh-fixture"
                 ])
      end)

    fixture = Jason.decode!(fixture_output)
    assert fixture["ok"] == true
    assert get_in(fixture, ["data", "data", "status"]) == "accepted"
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
          {:live_github_evidence, "live.github-evidence", "github", ["GH_TOKEN", "GITHUB_TOKEN"]},
          {:live_github_pr_cleanup, "live.github-pr-cleanup", "github",
           ["GH_TOKEN", "GITHUB_TOKEN"]}
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

      assert decoded["data"]["example_mode"] == "deterministic_fixture"
      assert decoded["data"]["deterministic_fixture?"] == true
      assert decoded["data"]["live_product_path?"] == false
      assert decoded["data"]["live_provider_effect?"] == false
      assert decoded["data"]["requires_live_product_path?"] == true
      assert decoded["data"]["provider_effect"]["live_provider_effect?"] == false

      assert decoded["refs"]["run_ref"] == "run:fixture"
      refute Map.has_key?(decoded["refs"], "source_publication_ref")
      refute String.contains?(output, "env-linear")
      refute String.contains?(output, "env-github")
      refute String.contains?(output, "env-codex")
    end
  end

  @tag :live_provider
  test "live-named commands do not dispatch provider effects without live product path" do
    for {operation, expected_operation, argv, stdin?} <- [
          {:live_linear_source, "live.linear-source",
           ["--json", "--api-key-stdin", "--trace-id", "trace:fixture-linear-source"], true},
          {:live_linear_current_states, "live.linear-current-states",
           [
             "--json",
             "--api-key-stdin",
             "--issue-ids",
             "lin-issue-321",
             "--trace-id",
             "trace:fixture-linear-current-states"
           ], true},
          {:live_linear_publication, "live.linear-publication",
           ["--json", "--api-key-stdin", "--trace-id", "trace:fixture-linear-publication"], true},
          {:live_linear_graphql_tool, "live.linear-graphql-tool",
           [
             "--json",
             "--api-key-stdin",
             "--query",
             "query Viewer { viewer { id } }",
             "--trace-id",
             "trace:fixture-linear-graphql"
           ], true},
          {:live_codex_turn, "live.codex-turn",
           ["--json", "--credential-available", "--trace-id", "trace:fixture-codex"], false},
          {:live_github_evidence, "live.github-evidence",
           [
             "--json",
             "--credential-available",
             "--repo",
             "nshkrdotcom/extravaganza",
             "--pull-number",
             "17",
             "--ref",
             "head-sha",
             "--trace-id",
             "trace:fixture-github"
           ], false},
          {:live_github_pr_cleanup, "live.github-pr-cleanup",
           [
             "--json",
             "--credential-available",
             "--repo",
             "nshkrdotcom/extravaganza",
             "--branch",
             "cleanup-branch",
             "--confirm-close",
             "--trace-id",
             "trace:fixture-github-cleanup"
           ], false}
        ] do
      output =
        if stdin? do
          capture_io("credential-value\n", fn ->
            assert :ok = HeadlessCLI.run(operation, argv)
          end)
        else
          capture_io(fn -> assert :ok = HeadlessCLI.run(operation, argv) end)
        end

      decoded = Jason.decode!(output)
      data = decoded["data"]
      provider_effect = data["provider_effect"]

      assert decoded["ok"] == true
      assert decoded["operation"] == expected_operation
      assert data["status"] == "skipped"
      assert data["example_mode"] == "deterministic_fixture"
      assert data["deterministic_fixture?"] == true
      assert data["live_product_path?"] == false
      assert data["live_provider_effect?"] == false
      assert data["requires_live_product_path?"] == true
      assert provider_effect["status"] == "skipped"
      assert provider_effect["skip_reason"]["code"] == "live_product_path_required"
      assert provider_effect["live_provider_effect?"] == false
      assert provider_effect["fixture_backed?"] == true
      assert data["credential_preflight"]["status"] == "requires_live_product_path"
      refute output =~ "credential-value"
    end

    refute_received {:fetch_source_candidates, _, _, _, _}
    refute_received {:current_source_states, _, _, _, _, _}
    refute_received {:publish_source, _, _, _, _}
    refute_received {:invoke_runtime_tool, _, _, _, _, _}
    refute_received {:start_agent_run, _, _, _}
    refute_received {:collect_evidence, _, _, _, _}
    refute_received {:invoke_resource_effect, _, _, _, _}
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
                   @guardrails_ack,
                   "--live-product-path",
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
    assert_authority_proof(decoded["data"]["provider_effect"], "linear", "issues-list")
    assert decoded["data"]["provider_effect"]["operation"] == "linear.issues.list"
    assert decoded["data"]["provider_effect"]["viewer_preflight?"] == true
    assert decoded["data"]["provider_effect"]["viewer_operation"] == "linear.users.get_self"
    assert decoded["data"]["provider_effect"]["viewer_provider_request_sent?"] == true
    assert decoded["data"]["provider_effect"]["viewer_provider_response_received?"] == true

    assert decoded["data"]["provider_effect"]["viewer_lower_request_ref"] =~
             "lower-request://linear/viewer"

    refute output =~ secret
    refute output =~ "live_provider_effect_deferred"

    assert_received {:fetch_source_candidates, tenant_id, :issue_tracker, source_binding, _opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
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
                   @guardrails_ack,
                   "--live-product-path",
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

    assert_received {:fetch_source_candidates, tenant_id, :issue_tracker, source_binding, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert source_binding.candidate_filters.state_names == ["Todo", "Backlog"]
    assert source_binding.candidate_filters.project_slug == "ENG"
    assert source_binding.candidate_filters.team_id == "team-linear"
    assert Keyword.fetch!(opts, :first) == 7
    assert Keyword.fetch!(opts, :cursor) == "cursor-1"
    assert Keyword.fetch!(opts, :api_key) == secret
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
                   @guardrails_ack,
                   "--live-product-path",
                   "--trace-id",
                   "trace:live-source-product"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["data"]["status"] == "completed"
    assert_received {:fetch_source_candidates, tenant_id, :issue_tracker, _source_binding, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert opts |> Keyword.fetch!(:pack_version) |> String.starts_with?("1.0.0-live.")
    assert Keyword.fetch!(opts, :api_key) == secret
    refute output =~ secret
  end

  @tag :live_provider
  test "linear source accepts explicit connection and credential refs without raw key material" do
    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_source, [
                   "--json",
                   @guardrails_ack,
                   "--live-product-path",
                   "--connection-id",
                   "connection-linear-existing",
                   "--credential-ref",
                   "credential-ref-linear-existing",
                   "--credential-lease-ref",
                   "credential-lease-linear-existing",
                   "--trace-id",
                   "trace:live-source-existing-connection"
                 ])
      end)

    decoded = Jason.decode!(output)
    preflight = decoded["data"]["credential_preflight"]

    assert decoded["ok"] == true
    assert decoded["data"]["status"] == "completed"
    assert preflight["status"] == "dispatchable"
    assert preflight["dispatch_binding"] == "connection_id"
    assert preflight["connection_id"] == "connection-linear-existing"
    assert preflight["credential_ref"] == "credential-ref-linear-existing"
    assert preflight["credential_lease_ref"] == "credential-lease-linear-existing"
    assert preflight["secret_material_present?"] == false
    assert preflight["secret_material_redacted?"] == true

    assert_received {:fetch_source_candidates, tenant_id, :issue_tracker, _source_binding, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert Keyword.fetch!(opts, :connection_id) == "connection-linear-existing"
    assert Keyword.fetch!(opts, :credential_ref) == "credential-ref-linear-existing"
    assert Keyword.fetch!(opts, :credential_lease_ref) == "credential-lease-linear-existing"
    refute Keyword.has_key?(opts, :api_key)
    refute output =~ "api_key"
  end

  @tag :live_provider
  test "linear source credential ref without connection binding renders redacted preflight skip" do
    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:live_linear_source, [
                   "--json",
                   "--credential-ref",
                   "credential-ref-linear-existing",
                   "--trace-id",
                   "trace:live-source-ref-only"
                 ])
      end)

    decoded = Jason.decode!(output)
    provider_effect = decoded["data"]["provider_effect"]
    preflight = decoded["data"]["credential_preflight"]

    assert decoded["ok"] == true
    assert decoded["data"]["status"] == "skipped"
    assert provider_effect["status"] == "skipped"
    assert provider_effect["skip_reason"]["code"] == "credential_ref_requires_connection_id"
    assert preflight["status"] == "missing_dispatch_binding"
    assert preflight["credential_ref"] == "credential-ref-linear-existing"
    assert preflight["secret_material_present?"] == false
    refute_received {:fetch_source_candidates, _, _, _, _}
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
                   @guardrails_ack,
                   "--live-product-path",
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

    assert_received {:fetch_source_candidates, tenant_id, :issue_tracker, source_binding, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    refute Map.has_key?(source_binding.candidate_filters, :assignee)
    assert Keyword.fetch!(opts, :api_key) == secret
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
                   @guardrails_ack,
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
                   @guardrails_ack,
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
                   @guardrails_ack,
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
    assert_authority_proof(provider_effect, "linear", "issues-list")
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

    assert_received {:current_source_states, tenant_id, :issue_tracker, issue_ids, source_binding,
                     opts}

    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert issue_ids == ["lin-issue-321", "lin-missing"]
    assert source_binding.candidate_filters.assignee == "me"
    assert Keyword.fetch!(opts, :api_key) == secret
    assert Keyword.fetch!(opts, :trace_id) == "trace:live-current-states"
  end

  @tag :live_provider
  test "codex turn live product path enters RuntimeGateway and confirms run-detail readback" do
    Application.put_env(:app_kit_core, :headless_backend, __MODULE__.CodexAgentBackend)

    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:live_codex_turn, [
                   "--json",
                   @guardrails_ack,
                   "--live-product-path",
                   "--trace-id",
                   "trace:live-codex-product"
                 ])
      end)

    decoded = Jason.decode!(output)
    data = decoded["data"]
    provider_effect = data["provider_effect"]
    preflight = data["credential_preflight"]

    assert decoded["ok"] == true
    assert decoded["operation"] == "live.codex-turn"
    assert data["status"] == "completed"
    assert preflight["status"] == "dispatchable"
    assert preflight["dispatch_binding"] == "app_config"
    assert preflight["credential_source"] == "app_config"
    assert preflight["secret_material_present?"] == false
    assert preflight["secret_material_redacted?"] == true

    assert data["product_path"]["appkit_surfaces"] == [
             "AppKit.RuntimeGateway",
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
    assert_authority_proof(provider_effect, "codex", "session-turn")
    assert provider_effect["first_prompt_confirmed?"] == true
    assert provider_effect["prompt_ref"] == "prompt://extravaganza/live-codex-turn"
    assert provider_effect["prompt_hash"] =~ "sha256:"

    assert provider_effect["prompt_source_ref"] ==
             "workflow://extravaganza/live-codex-turn/default"

    assert provider_effect["prompt_rendered?"] == true
    assert provider_effect["prompt_body_redacted?"] == true
    assert provider_effect["prompt_body_included?"] == false
    assert provider_effect["turn_count"] == 2
    assert provider_effect["max_turns"] == 2
    assert provider_effect["continuation_turn_count"] == 1
    assert provider_effect["continuation_turns_confirmed?"] == true

    assert provider_effect["continuation_guidance_ref"] ==
             "continuation-guidance://extravaganza/live-codex-turn/2"

    assert provider_effect["continuation_guidance_rendered?"] == true
    assert provider_effect["continuation_prompt_body_redacted?"] == true
    assert provider_effect["continuation_prompt_body_included?"] == false
    assert provider_effect["first_prompt_reused_on_continuation?"] == false
    assert provider_effect["max_turns_reached?"] == true
    assert provider_effect["session_start_confirmed?"] == true
    assert provider_effect["session_ref"] == "session://codex/live-product"
    assert provider_effect["runtime_control_session_ref"] == "runtime-session://asm-live-product"
    assert provider_effect["session_start_event_kind"] == "codex.session.started"

    assert provider_effect["session_start_lower_receipt_ref"] ==
             "lower-receipt://codex/session-start/asm-live-product/started"

    assert provider_effect["session_stop_confirmed?"] == true
    assert provider_effect["session_stop_status"] == "stopped"

    assert provider_effect["session_stop_lower_request_ref"] ==
             "lower-request://codex/session-stop"

    assert provider_effect["session_stop_lower_receipt_ref"] ==
             "lower-receipt://codex/session-stop/asm-live-product/stopped"

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
    refute Map.has_key?(provider_effect, "codex_session_id")
    assert provider_effect["event_stream_confirmed?"] == true
    assert provider_effect["event_count"] == 12
    assert provider_effect["event_terminal_status"] == "completed"
    assert provider_effect["completed_event_count"] == 1
    assert provider_effect["failed_event_count"] == 1
    assert provider_effect["cancelled_event_count"] == 1
    assert provider_effect["malformed_event_count"] == 1
    assert provider_effect["timeout_event_count"] == 1
    assert provider_effect["approval_event_count"] == 2
    assert provider_effect["approval_required_count"] == 1
    assert provider_effect["approval_auto_approved_count"] == 1
    assert provider_effect["user_input_event_count"] == 2
    assert provider_effect["user_input_required_count"] == 1
    assert provider_effect["user_input_auto_answered_count"] == 1
    assert provider_effect["token_usage_input_tokens"] == 10
    assert provider_effect["token_usage_output_tokens"] == 4
    assert provider_effect["token_usage_total_tokens"] == 14
    assert provider_effect["token_usage_source"] == "thread_token_usage_total"
    assert provider_effect["token_accounting_confirmed?"] == true
    assert provider_effect["token_totals_input_tokens"] == 12
    assert provider_effect["token_totals_output_tokens"] == 5
    assert provider_effect["token_totals_total_tokens"] == 17
    assert provider_effect["token_totals_cached_input_tokens"] == 0
    assert provider_effect["token_totals_source"] == "runtime:event:codex-token-accounting"
    assert provider_effect["runtime_state"] == "completed"
    assert provider_effect["configured_stall_timeout_ms"] == 300_000
    assert provider_effect["stall_decision_present?"] == false
    refute Map.has_key?(provider_effect, "stall_elapsed_ms")
    refute Map.has_key?(provider_effect, "stall_safe_action")
    assert provider_effect["rate_limits_present?"] == true
    assert provider_effect["rate_limit_id"] == "codex"
    assert provider_effect["rate_limit_primary_remaining"] == 90
    assert provider_effect["rate_limit_primary_limit"] == 100
    assert provider_effect["last_codex_message_event_kind"] == "codex.agent_message.updated"
    assert provider_effect["last_codex_message_summary"] == "codex agent message updated"
    assert provider_effect["last_codex_message_body_included?"] == false

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
    assert request.params.initial_input.input_ref == "prompt://extravaganza/live-codex-turn"
    assert request.params.initial_input.content_hash == provider_effect["prompt_hash"]
    assert request.params.initial_input.source_ref == provider_effect["prompt_source_ref"]
    assert request.params.initial_input.rendered? == true
    assert request.params.initial_input.body_redacted? == true
    assert request.params.initial_input.body =~ "Issue: LIVE-CODEX-001"
    assert request.params.initial_input.body =~ "Confirm the live Codex product path"
    assert request.params.max_turns == 2
    assert request.params.timeout_policy.stall_timeout_ms == 300_000
    assert request.params.continuation_policy.mode == "until_max_turns"
    assert request.params.continuation_policy.active_state? == true

    assert request.params.continuation_input.input_ref ==
             "continuation-guidance://extravaganza/live-codex-turn/2"

    assert request.params.continuation_input.body =~ "Continuation guidance"
    refute request.params.continuation_input.body =~ "Issue: LIVE-CODEX-001"
    refute request.params.continuation_input.body =~ "Confirm the live Codex product path"
    refute Map.has_key?(request.params, :prompt)
    assert Keyword.fetch!(opts, :trace_id) == "trace:live-codex-product"

    assert_received {:runtime_run_detail, "run://codex/live-product", readback_request, _opts}
    assert readback_request.capability_id == "codex.session.turn"
    refute Map.has_key?(provider_effect, "prompt")
    refute output =~ "SECRET_PROMPT_BODY_DO_NOT_EXPOSE"
    refute output =~ "Preserve unrelated user work"
    refute output =~ "FIRST_PROMPT_SECRET_BODY"
    refute output =~ "STREAM_BODY_DO_NOT_EXPOSE"
    refute output =~ "env-codex"
    refute output =~ "live_provider_effect_deferred"
  end

  @tag :live_provider
  test "github evidence live product path fetches provider evidence through AppKit without writes" do
    Application.put_env(:app_kit_core, :generic_backend, __MODULE__.GenericRuntimeBackend)

    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:live_github_evidence, [
                   "--json",
                   @guardrails_ack,
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
    preflight = data["credential_preflight"]

    assert decoded["ok"] == true
    assert decoded["operation"] == "live.github-evidence"
    assert data["status"] == "completed"
    assert preflight["status"] == "dispatchable"
    assert preflight["dispatch_binding"] == "app_config"
    assert preflight["credential_source"] == "app_config"
    assert preflight["secret_material_present?"] == false
    assert preflight["secret_material_redacted?"] == true

    assert data["product_path"]["appkit_surfaces"] == [
             "AppKit.RuntimeGateway",
             "AppKit.HeadlessSurface"
           ]

    assert provider_effect["status"] == "receipt_recorded"
    assert provider_effect["effect"] == "github_pr_evidence"
    assert provider_effect["operation"] == "github.pr.evidence"
    assert provider_effect["credential_present?"] == true
    assert provider_effect["credential_redeemed?"] == true
    assert provider_effect["provider_request_sent?"] == true
    assert provider_effect["provider_response_received?"] == true
    assert provider_effect["receipt_recorded?"] == true
    assert provider_effect["product_readback_confirmed?"] == true
    assert_authority_proof(provider_effect, "github", "pr-fetch")
    assert provider_effect["repo"] == "nshkrdotcom/extravaganza"
    assert provider_effect["pull_number"] == 17
    assert provider_effect["head_sha"] == "head-sha"
    assert provider_effect["provider_ids"]["pull_request"] == "17"
    assert provider_effect["provider_ids"]["reviews"] == ["1", "2"]
    assert provider_effect["provider_ids"]["review_comments"] == ["11"]
    assert provider_effect["provider_ids"]["check_runs"] == ["100"]
    assert provider_effect["provider_refs"]["pull_request"] =~ "/pull/17"

    assert provider_effect["receipt_refs"]["evidence_ref"] ==
             "evidence://github-pr/nshkrdotcom/extravaganza/17/test"

    assert [%{"lower_receipt_ref" => "lower-receipt://github/pr-fetch/succeeded"}] =
             provider_effect["operation_receipts"]

    assert provider_effect["write_operations"] == []
    assert provider_effect["fixture_setup_required?"] == false
    assert data["lower_request_ref"] == "lower-request://github/pr-fetch"
    assert data["lower_receipt_ref"] == "lower-receipt://github/pr-fetch/succeeded"
    assert data["connector_manifest_ref"] == "manifest://jido/connectors/github@test"
    assert data["capability_negotiation_ref"] == "cap-neg://github/pr-fetch"
    refute Map.has_key?(data, "source_publication_ref")

    assert_received {:collect_evidence, tenant_id, :proposed_change_evidence, request, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert request.repo == "nshkrdotcom/extravaganza"
    assert request.pull_number == 17
    assert request.ref == "head-sha"
    assert Keyword.fetch!(opts, :trace_id) == "trace:live-github-product"
    refute output =~ "env-github"
    refute output =~ "live_provider_effect_deferred"
  end

  @tag :live_provider
  test "github cleanup live product path closes matching branch PRs through AppKit with confirmation" do
    Application.put_env(:app_kit_core, :generic_backend, __MODULE__.GenericRuntimeBackend)

    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:live_github_pr_cleanup, [
                   "--json",
                   @guardrails_ack,
                   "--live-product-path",
                   "--repo",
                   "nshkrdotcom/extravaganza",
                   "--branch",
                   "cleanup-branch",
                   "--confirm-close",
                   "--trace-id",
                   "trace:live-github-cleanup"
                 ])
      end)

    decoded = Jason.decode!(output)
    data = decoded["data"]
    provider_effect = data["provider_effect"]
    preflight = data["credential_preflight"]

    assert decoded["ok"] == true
    assert decoded["operation"] == "live.github-pr-cleanup"
    assert data["status"] == "completed"
    assert preflight["status"] == "dispatchable"
    assert preflight["dispatch_binding"] == "app_config"
    assert provider_effect["status"] == "receipt_recorded"
    assert provider_effect["operation"] == "github.pr.branch_cleanup"
    assert provider_effect["resource_effect_role_ref"] == "proposed_change_cleanup"
    assert provider_effect["repo"] == "nshkrdotcom/extravaganza"
    assert provider_effect["branch"] == "cleanup-branch"
    assert provider_effect["pull_numbers"] == [17]
    assert provider_effect["closed_pull_numbers"] == [17]
    assert provider_effect["write_operations"] == ["github.comment.create", "github.pr.update"]
    assert provider_effect["provider_request_sent?"] == true
    assert provider_effect["provider_response_received?"] == true
    assert provider_effect["receipt_recorded?"] == true
    assert provider_effect["product_readback_confirmed?"] == true

    assert [
             %{
               "capability_id" => "github.pr.update",
               "lower_request_ref" => "lower-request://github/pr-cleanup",
               "lower_receipt_ref" => "lower-receipt://github/pr-cleanup/succeeded"
             }
           ] = provider_effect["operation_receipts"]

    assert_authority_proof(provider_effect, "github", "pr-cleanup")
    assert data["lower_request_ref"] == "lower-request://github/pr-cleanup"
    assert data["lower_receipt_ref"] == "lower-receipt://github/pr-cleanup/succeeded"

    assert_received {:invoke_resource_effect, tenant_id, :proposed_change_cleanup, request, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert request.repo == "nshkrdotcom/extravaganza"
    assert request.branch == "cleanup-branch"
    assert request.confirm_close? == true
    assert Keyword.fetch!(opts, :trace_id) == "trace:live-github-cleanup"
    refute output =~ "env-github"
  end

  @tag :live_provider
  test "aggregate live smoke product path completes only with all provider effects on one trace" do
    Application.put_env(:app_kit_core, :headless_backend, __MODULE__.CodexAgentBackend)
    Application.put_env(:app_kit_core, :generic_backend, __MODULE__.GenericRuntimeBackend)

    secret = "linear-secret-value"

    output =
      capture_io(secret <> "\n", fn ->
        assert :ok =
                 HeadlessCLI.run(:live_smoke, [
                   "--json",
                   "--api-key-stdin",
                   @guardrails_ack,
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

    assert_received {:fetch_source_candidates, tenant_id, :issue_tracker, _source_binding,
                     source_opts}

    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert Keyword.fetch!(source_opts, :trace_id) == "trace:live-smoke-product"
    assert Keyword.fetch!(source_opts, :api_key) == secret

    assert_received {:current_source_states, _tenant_id, :issue_tracker, ["lin-issue-321"],
                     current_source_binding, current_opts}

    assert current_source_binding.candidate_filters.assignee == "me"
    assert Keyword.fetch!(current_opts, :trace_id) == "trace:live-smoke-product"
    assert Keyword.fetch!(current_opts, :api_key) == secret

    assert_received {:start_agent_run, _tenant_id, request, codex_opts}
    assert request.trace_id == "trace:live-smoke-product"
    assert Keyword.fetch!(codex_opts, :trace_id) == "trace:live-smoke-product"

    assert_received {:runtime_run_detail, "run://codex/live-product", _readback_request,
                     codex_readback_opts}

    assert Keyword.fetch!(codex_readback_opts, :trace_id) == "trace:live-smoke-product"

    assert_received {:publish_source, _tenant_id, :source_publication, attrs, publication_opts}
    assert attrs.issue_id == "lin-issue-321"
    assert attrs.source_binding.source_binding_id == "linear-primary"
    assert Keyword.fetch!(publication_opts, :trace_id) == "trace:live-smoke-product"
    assert Keyword.fetch!(publication_opts, :api_key) == secret

    assert_received {:invoke_runtime_tool, _tenant_id, :issue_graphql_tool, :execute_query,
                     graphql_attrs, graphql_opts}

    assert graphql_attrs.query == "query Viewer { viewer { id } }"
    assert Keyword.fetch!(graphql_opts, :trace_id) == "trace:live-smoke-product"
    assert Keyword.fetch!(graphql_opts, :api_key) == secret

    assert_received {:collect_evidence, _tenant_id, :proposed_change_evidence, github_request,
                     github_opts}

    assert github_request.repo == "nshkrdotcom/extravaganza"
    assert github_request.pull_number == 17
    assert github_request.ref == "head-sha"
    assert Keyword.fetch!(github_opts, :trace_id) == "trace:live-smoke-product"
  end

  @tag :live_provider
  test "linear source stdin default fixture path requires explicit live product path" do
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
    assert decoded["data"]["status"] == "skipped"
    assert decoded["data"]["example_mode"] == "deterministic_fixture"
    assert decoded["data"]["live_provider_effect?"] == false

    assert decoded["data"]["provider_effect"]["skip_reason"]["code"] ==
             "live_product_path_required"

    refute_received {:fetch_source_candidates, _, _, _, _}
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
                   @guardrails_ack,
                   "--live-product-path",
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
    assert_authority_proof(decoded["data"]["provider_effect"], "linear", "comments-create")
    assert decoded["data"]["provider_effect"]["comment_ref"] == "linear-comment://comment-1"
    assert decoded["refs"]["source_publication_ref"] == "source-publication://linear-primary/test"
    refute output =~ secret
    refute output =~ "live_provider_effect_deferred"

    assert_received {:fetch_source_candidates, tenant_id, :issue_tracker, source_binding,
                     _source_opts}

    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert source_binding.source_binding_id == "linear-primary"

    assert_received {:publish_source, tenant_id, :source_publication, attrs, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert attrs.source_binding.source_binding_id == "linear-primary"
    assert attrs.source_binding_id == "linear-primary"
    assert attrs.issue_id == "lin-issue-321"
    assert Keyword.fetch!(opts, :api_key) == secret
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
                   @guardrails_ack,
                   "--live-product-path",
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
    assert decoded["data"]["provider_effect"]["comment_ref"] == "linear-comment://comment-1"
    assert decoded["data"]["provider_effect"]["workpad_refs"] == ["linear-comment://comment-1"]
    refute Map.has_key?(decoded["data"]["provider_effect"], "linear_comment_id")
    refute output =~ secret

    assert_received {:publish_source, tenant_id, :source_publication, attrs, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert attrs.comment_id == "comment-1"
    assert attrs.body == "Updated by product path"
    assert Keyword.fetch!(opts, :api_key) == secret
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
                   @guardrails_ack,
                   "--live-product-path",
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

    assert_received {:publish_source, tenant_id, :source_publication, attrs, _opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
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
                   @guardrails_ack,
                   "--live-product-path",
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
    assert_authority_proof(decoded["data"]["provider_effect"], "linear", "issues-update")
    refute output =~ secret

    assert_received {:publish_source, tenant_id, :source_publication, attrs, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert attrs.issue_id == "lin-issue-321"
    assert attrs.state_name == "Done"
    assert attrs.team_id == "team-linear"
    assert Keyword.fetch!(opts, :api_key) == secret
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
                   @guardrails_ack,
                   "--live-product-path",
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

    assert_received {:publish_source, tenant_id, :source_publication, attrs, opts}
    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert attrs.issue_id == "lin-issue-321"
    assert attrs.source_binding.source_binding_id == "linear-primary"
    assert Keyword.fetch!(opts, :dry_run?) == true
    assert Keyword.fetch!(opts, :api_key) == secret
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
                   @guardrails_ack,
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

    assert provider_effect["appkit_surfaces"] == [
             "AppKit.RuntimeGateway",
             "AppKit.HeadlessSurface"
           ]

    assert_authority_proof(provider_effect, "linear", "graphql-execute")
    assert dynamic_response["success"] == true

    assert Jason.decode!(dynamic_response["output"]) == %{
             "data" => %{"viewer" => %{"id" => "usr-linear-viewer"}}
           }

    assert_received {:invoke_runtime_tool, tenant_id, :issue_graphql_tool, :execute_query, attrs,
                     opts}

    assert String.starts_with?(tenant_id, "extravaganza-live-")
    assert attrs.query == "query Viewer { viewer { id } }"
    assert attrs.variables == %{"includeTeams" => false}
    assert Keyword.fetch!(opts, :api_key) == secret
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
    assert decoded["data"]["example_mode"] == "deterministic_fixture"
    assert decoded["data"]["deterministic_fixture?"] == true
    assert decoded["data"]["live_product_path?"] == false
    assert decoded["data"]["live_provider_effect?"] == false
    assert decoded["data"]["requires_live_product_path?"] == true
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
    assert decoded["data"]["example_mode"] == "deterministic_fixture"
    assert decoded["data"]["live_provider_effect?"] == false
    assert decoded["data"]["product_path"]["proof_source"] == "fixture_headless_surface"

    assert decoded["data"]["product_path"]["lower_path_status"] ==
             "skipped_before_live_provider_effect"

    assert decoded["refs"]["run_ref"] == "run:fixture"
  end

  test "CLI emits stable JSON envelopes for fixture state, run, evidence, and events" do
    for {operation, argv, schema_ref, required_refs} <- [
          {:state, common_args(), "headless_state_snapshot.v1", []},
          {:run, ["run:fixture" | common_args()], "headless_run_detail.v1",
           ["run_ref", "lower_request_ref", "lower_receipt_ref"]},
          {:evidence, ["run:fixture" | common_args()], "headless_evidence_chain.v1",
           ["run_ref", "source_publication_ref"]},
          {:events, ["--run", "run:fixture" | common_args()], "headless_events.v1",
           ["run_ref", "event_page_ref"]},
          {:stop, ["--confirm-no-active-lower-runs" | common_args()], "headless_shutdown.v1", []}
        ] do
      output = capture_io(fn -> assert :ok = HeadlessCLI.run(operation, argv) end)
      decoded = Jason.decode!(output)

      assert decoded["ok"] == true
      assert decoded["schema"] == "extravaganza.headless.response.v1"
      assert decoded["operation"] == Atom.to_string(operation)
      assert decoded["trace_id"] == "trace:examples"
      assert decoded["data"]["schema_ref"] == schema_ref

      for ref <- required_refs do
        assert is_binary(decoded["refs"][ref])
      end

      refute String.contains?(output, "workspace_path")
      refute String.contains?(output, "/home/")
    end
  end

  test "golden headless examples are valid standard envelopes" do
    expected = %{
      "error_projection_unavailable.json" => {:error, "run_detail", nil, []},
      "events.json" => {:ok, "events", "headless_events.v1", ["event_page_ref", "run_ref"]},
      "evidence.json" =>
        {:ok, "evidence", "headless_evidence_chain.v1",
         ["authority_ref", "run_ref", "source_publication_ref"]},
      "run.json" =>
        {:ok, "run", "headless_run_detail.v1",
         ["authority_ref", "lower_receipt_ref", "lower_request_ref", "run_ref"]},
      "state.json" => {:ok, "state", "headless_state_snapshot.v1", []}
    }

    for path <- Path.wildcard("examples/headless/*.json") do
      body = path |> File.read!() |> Jason.decode!()
      filename = Path.basename(path)
      {status, operation, schema_ref, required_refs} = Map.fetch!(expected, filename)

      assert body["ok"] == (status == :ok)

      assert body["schema"] in [
               "extravaganza.headless.response.v1",
               "extravaganza.headless.error.v1"
             ]

      assert body["operation"] == operation

      if schema_ref do
        assert body["data"]["schema_ref"] == schema_ref
      end

      for ref <- required_refs do
        assert is_binary(body["refs"][ref])
      end

      encoded = Jason.encode!(body)
      refute String.contains?(encoded, "workspace_path")
      refute String.contains?(encoded, "/home/")
      refute String.contains?(encoded, "api_key")
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
          "scripts/headless/preflight.exs",
          "scripts/headless/stop.exs",
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

  defp assert_authority_proof(provider_effect, provider, operation_slug) do
    assert provider_effect["authority_authorized?"] == true

    assert provider_effect["authority_handoff_ref"] ==
             "authority-handoff://#{provider}/#{operation_slug}"

    assert provider_effect["authority_packet_ref"] ==
             "authority-packet://#{provider}/#{operation_slug}"

    assert provider_effect["connector_binding_ref"] == "connector-binding://#{provider}/primary"
    assert provider_effect["credential_lease_ref"] == "credential-lease://#{provider}/primary"
    assert provider_effect["authority_raw_material_present?"] == false
  end

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
    @session_stop_lower_request_ref "lower-request://codex/session-stop"
    @session_stop_lower_receipt_ref "lower-receipt://codex/session-stop/asm-live-product/stopped"
    @provider_session_id "codex-provider-thread-live-product"
    @provider_turn_id "codex-provider-turn-live-product"
    @app_server_jsonrpc_methods ["initialize", "initialized", "thread/start", "turn/start"]
    @observed_at ~U[2026-05-12 00:00:00Z]

    @impl true
    def start_agent_run(context, request, opts) do
      if pid = Process.get(:headless_examples_test_pid) do
        send(pid, {:start_agent_run, context.tenant_ref.id, request, opts})
      end

      initial_input = Map.fetch!(request.params, :initial_input)
      continuation_input = Map.fetch!(request.params, :continuation_input)

      Process.put(:codex_agent_prompt_readback, %{
        "confirmed?" => true,
        "prompt_ref" => Map.fetch!(initial_input, :input_ref),
        "prompt_hash" => Map.fetch!(initial_input, :content_hash),
        "prompt_source_ref" => Map.fetch!(initial_input, :source_ref),
        "prompt_rendered?" => Map.fetch!(initial_input, :rendered?),
        "prompt_body_redacted?" => Map.fetch!(initial_input, :body_redacted?),
        "prompt_body_included?" => false,
        "source" => "product_profile"
      })

      Process.put(:codex_agent_continuation_readback, %{
        "confirmed?" => true,
        "turn_count" => Map.fetch!(request.params, :max_turns),
        "continuation_turn_count" => 1,
        "max_turns" => Map.fetch!(request.params, :max_turns),
        "max_turns_reached?" => true,
        "continuation_guidance_ref" => Map.fetch!(continuation_input, :input_ref),
        "continuation_guidance_hash" => Map.fetch!(continuation_input, :content_hash),
        "continuation_guidance_source_ref" => Map.fetch!(continuation_input, :source_ref),
        "continuation_guidance_rendered?" => Map.fetch!(continuation_input, :rendered?),
        "continuation_prompt_body_redacted?" => Map.fetch!(continuation_input, :body_redacted?),
        "continuation_prompt_body_included?" => false,
        "first_prompt_reused_on_continuation?" => false
      })

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

      first_prompt = Process.get(:codex_agent_prompt_readback)
      continuation = Process.get(:codex_agent_continuation_readback)

      with {:ok, runtime_row} <-
             RuntimeRow.new(%{
               subject_ref: "subject://extravaganza/live-codex-turn",
               run_ref: run_ref,
               workflow_ref: @workflow_ref,
               state: "completed",
               updated_at: @observed_at,
               token_totals: %{
                 total_input_tokens: 12,
                 total_output_tokens: 5,
                 total_tokens: 17,
                 cached_input_tokens: 0,
                 source: "runtime:event:codex-token-accounting"
               },
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
                 "codex_app_server_session_stop" => %{
                   "confirmed?" => true,
                   "operation" => "codex.session.stop",
                   "status" => "stopped",
                   "runtime_control_session_ref" => @runtime_control_session_ref,
                   "lower_request_ref" => @session_stop_lower_request_ref,
                   "lower_receipt_ref" => @session_stop_lower_receipt_ref
                 },
                 "codex_first_prompt" => first_prompt,
                 "codex_continuation" => continuation,
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
                 "codex_event_stream" => %{
                   "confirmed?" => true,
                   "event_count" => 12,
                   "terminal_status" => "completed",
                   "completed_event_count" => 1,
                   "failed_event_count" => 1,
                   "cancelled_event_count" => 1,
                   "malformed_event_count" => 1,
                   "timeout_event_count" => 1,
                   "approval_event_count" => 2,
                   "approval_required_count" => 1,
                   "approval_auto_approved_count" => 1,
                   "user_input_event_count" => 2,
                   "user_input_required_count" => 1,
                   "user_input_auto_answered_count" => 1,
                   "token_usage" => %{
                     "input_tokens" => 10,
                     "output_tokens" => 4,
                     "total_tokens" => 14,
                     "source" => "thread_token_usage_total"
                   },
                   "rate_limits_present?" => true,
                   "rate_limit_id" => "codex",
                   "rate_limit_primary_remaining" => 90,
                   "rate_limit_primary_limit" => 100,
                   "last_message" => %{
                     "event_kind" => "codex.agent_message.updated",
                     "summary" => "codex agent message updated",
                     "body_redacted?" => true,
                     "body_included?" => false
                   }
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
           {:ok, first_prompt_event} <-
             RuntimeEventRow.new(%{
               event_ref: "event://codex/live-product/first-prompt",
               event_seq: 2,
               event_kind: "codex.first_prompt.confirmed",
               observed_at: @observed_at,
               subject_ref: "subject://extravaganza/live-codex-turn",
               run_ref: run_ref,
               workflow_ref: @workflow_ref,
               session_ref: @runtime_control_session_ref,
               turn_ref: @turn_ref,
               payload_ref: "payload://codex/live-product/first-prompt",
               extensions: first_prompt
             }),
           {:ok, app_server_protocol_event} <-
             RuntimeEventRow.new(%{
               event_ref: "event://codex/live-product/app-server-protocol",
               event_seq: 3,
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
           {:ok, continuation_event} <-
             RuntimeEventRow.new(%{
               event_ref: "event://codex/live-product/continuation-2",
               event_seq: 4,
               event_kind: "codex.continuation_turn.confirmed",
               observed_at: @observed_at,
               subject_ref: "subject://extravaganza/live-codex-turn",
               run_ref: run_ref,
               workflow_ref: @workflow_ref,
               session_ref: @runtime_control_session_ref,
               turn_ref: "turn://codex/live-product/2",
               payload_ref: "payload://codex/live-product/continuation-2",
               extensions: continuation
             }),
           {:ok, session_stop_event} <-
             RuntimeEventRow.new(%{
               event_ref: "event://codex/live-product/session-stop",
               event_seq: 5,
               event_kind: "codex.session.stopped",
               observed_at: @observed_at,
               subject_ref: "subject://extravaganza/live-codex-turn",
               run_ref: run_ref,
               workflow_ref: @workflow_ref,
               session_ref: @runtime_control_session_ref,
               turn_ref: "turn://codex/live-product/2",
               payload_ref: "payload://codex/live-product/session-stop",
               extensions: %{
                 "lower_request_ref" => @session_stop_lower_request_ref,
                 "lower_receipt_ref" => @session_stop_lower_receipt_ref,
                 "status" => "stopped"
               }
             }),
           {:ok, event} <-
             RuntimeEventRow.new(%{
               event_ref: "event://codex/live-product/terminal",
               event_seq: 6,
               event_kind: "run.terminal",
               observed_at: @observed_at,
               subject_ref: "subject://extravaganza/live-codex-turn",
               run_ref: run_ref,
               workflow_ref: @workflow_ref,
               turn_ref: "turn://codex/live-product/2",
               payload_ref: "payload://codex/live-product/terminal"
             }) do
        RuntimeRunDetail.new(%{
          run_ref: run_ref,
          runtime_row: runtime_row,
          events: [
            session_start_event,
            first_prompt_event,
            app_server_protocol_event,
            continuation_event,
            session_stop_event,
            event
          ],
          turns: [
            %{
              "turn_ref" => @turn_ref,
              "turn_index" => 1,
              "status" => "completed",
              "session_ref" => @session_ref,
              "operation" => "codex.session.turn",
              "authority_authorized?" => true,
              "authority_handoff_ref" => "authority-handoff://codex/session-turn",
              "authority_packet_ref" => "authority-packet://codex/session-turn",
              "connector_binding_ref" => "connector-binding://codex/primary",
              "credential_lease_ref" => "credential-lease://codex/primary",
              "authority_raw_material_present?" => false,
              "credential_redeemed?" => true,
              "provider_request_sent?" => true,
              "provider_response_received?" => true,
              "first_prompt_confirmed?" => true,
              "prompt_ref" => first_prompt["prompt_ref"],
              "prompt_hash" => first_prompt["prompt_hash"],
              "prompt_source_ref" => first_prompt["prompt_source_ref"],
              "prompt_rendered?" => first_prompt["prompt_rendered?"],
              "prompt_body_redacted?" => first_prompt["prompt_body_redacted?"],
              "prompt_body_included?" => first_prompt["prompt_body_included?"],
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
            },
            %{
              "turn_ref" => "turn://codex/live-product/2",
              "turn_index" => 2,
              "status" => "completed",
              "session_ref" => @session_ref,
              "operation" => "codex.session.turn",
              "credential_redeemed?" => true,
              "provider_request_sent?" => true,
              "provider_response_received?" => true,
              "continuation?" => true,
              "continuation_guidance_ref" => continuation["continuation_guidance_ref"],
              "continuation_guidance_hash" => continuation["continuation_guidance_hash"],
              "continuation_guidance_source_ref" =>
                continuation["continuation_guidance_source_ref"],
              "continuation_guidance_rendered?" =>
                continuation["continuation_guidance_rendered?"],
              "continuation_prompt_body_redacted?" =>
                continuation["continuation_prompt_body_redacted?"],
              "continuation_prompt_body_included?" =>
                continuation["continuation_prompt_body_included?"],
              "first_prompt_reused_on_continuation?" =>
                continuation["first_prompt_reused_on_continuation?"],
              "provider_session_id" => @provider_session_id,
              "provider_turn_id" => "codex-provider-turn-live-product-2",
              "lower_request_ref" => "lower-request://codex/session-turn/2",
              "lower_receipt_ref" => "lower-receipt://codex/session-turn/2/succeeded"
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

    def collect_evidence(context, evidence_role_ref, request, opts) do
      if pid = Process.get(:headless_examples_test_pid) do
        send(pid, {:collect_evidence, context.tenant_ref.id, evidence_role_ref, request, opts})
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
        metadata: %{
          "source" => "test",
          "authority_handoff" => %{
            "authorized?" => true,
            "handoff_ref" => "authority-handoff://github/pr-fetch",
            "authority_packet_ref" => "authority-packet://github/pr-fetch",
            "connector_binding_ref" => "connector-binding://github/primary",
            "credential_lease_ref" => "credential-lease://github/primary",
            "raw_material_present?" => false
          }
        }
      })
    end

    def invoke_resource_effect(context, resource_effect_role_ref, request, opts) do
      if pid = Process.get(:headless_examples_test_pid) do
        send(
          pid,
          {:invoke_resource_effect, context.tenant_ref.id, resource_effect_role_ref, request,
           opts}
        )
      end

      GitHubPrBranchCleanupReceipt.new(%{
        effect_ref: "live-effect://github/pr-branch-cleanup/test",
        tenant_ref: context.tenant_ref.id,
        provider: "github",
        effect: "github_pr_branch_cleanup",
        status: :receipt_recorded,
        capability_ids: ["github.pr.list", "github.comment.create", "github.pr.update"],
        repo: request.repo,
        branch: request.branch,
        pull_numbers: [17],
        closed_pull_numbers: [17],
        credential_present?: true,
        credential_redeemed?: true,
        provider_request_sent?: true,
        provider_response_received?: true,
        receipt_recorded?: true,
        product_readback_confirmed?: true,
        write_operations: ["github.comment.create", "github.pr.update"],
        provider_ids: %{pull_requests: ["17"]},
        provider_refs: %{pull_requests: ["https://github.com/nshkrdotcom/extravaganza/pull/17"]},
        counts: %{matched_count: 1, closed_count: 1, comment_count: 1},
        receipt_refs: %{
          lower_request_refs: ["lower-request://github/pr-cleanup"],
          lower_receipt_refs: ["lower-receipt://github/pr-cleanup/succeeded"]
        },
        operation_receipts: [
          %{
            capability_id: "github.pr.update",
            capability_negotiation_ref: "cap-neg://github/pr-cleanup",
            connector_manifest_ref: "manifest://jido/connectors/github@test",
            lower_request_ref: "lower-request://github/pr-cleanup",
            lower_receipt_ref: "lower-receipt://github/pr-cleanup/succeeded"
          }
        ],
        metadata: %{
          "authority_handoff" => %{
            "authorized?" => true,
            "handoff_ref" => "authority-handoff://github/pr-cleanup",
            "authority_packet_ref" => "authority-packet://github/pr-cleanup",
            "connector_binding_ref" => "connector-binding://github/primary",
            "credential_lease_ref" => "credential-lease://github/primary",
            "raw_material_present?" => false
          }
        }
      })
    end
  end

  defmodule SourceBackend do
    @behaviour AppKit.Core.Backends.SourceBackend

    @impl true
    def sync_source(_context, source_role_ref, _source_page, _opts),
      do: {:ok, %{source_role_ref: source_role_ref}}

    @impl true
    def current_states(context, source_role_ref, request, opts) do
      issue_ids = Map.fetch!(request, :issue_ids)
      source_binding = Map.fetch!(request, :source_binding)

      if pid = Process.get(:headless_examples_test_pid) do
        send(
          pid,
          {:current_source_states, context.tenant_ref.id, source_role_ref, issue_ids,
           source_binding, opts}
        )
      end

      result = %{
        source_role_ref: source_role_ref,
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
      }

      {:ok, Map.merge(result, authority_handoff("issues-list"))}
    end

    @impl true
    def fetch_candidates(context, source_role_ref, request, opts) do
      source_binding = Map.fetch!(request, :source_binding)

      if pid = Process.get(:headless_examples_test_pid) do
        send(
          pid,
          {:fetch_source_candidates, context.tenant_ref.id, source_role_ref, source_binding, opts}
        )
      end

      if response = Process.get(:headless_examples_source_response) do
        response
      else
        default_fetch_source_candidates(source_role_ref, source_binding)
      end
    end

    defp default_fetch_source_candidates(source_role_ref, source_binding) do
      result = %{
        source_role_ref: source_role_ref,
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
      }

      {:ok, Map.merge(result, authority_handoff("issues-list"))}
    end

    @impl true
    def publish_source(context, publication_role_ref, attrs, opts) do
      if pid = Process.get(:headless_examples_test_pid) do
        send(pid, {:publish_source, context.tenant_ref.id, publication_role_ref, attrs, opts})
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
              comment_ref: "linear-comment://comment-created",
              workpad_refs: ["linear-comment://comment-created"]
            }

          Map.get(attrs, :comment_id) ->
            comment_ref = "linear-comment://#{attrs.comment_id}"

            %{
              source_publication_receipt_ref: "source-publication://linear-primary/update",
              source_publish_ref: attrs.source_publish_ref,
              source_binding_id: attrs.source_binding_id,
              source_ref: attrs.source_ref,
              status: "published",
              capability_id: "linear.comments.update",
              lower_request_ref: "lower-request://linear/publication-update",
              lower_receipt_ref: "lower-receipt://linear/publication-update",
              comment_ref: comment_ref,
              workpad_refs: [comment_ref]
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
              comment_ref: "linear-comment://comment-1",
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
       }
       |> Map.merge(publication_authority_handoff(receipt))}
    end

    def invoke_runtime_tool(context, tool_role_ref, operation_role_ref, attrs, opts) do
      if pid = Process.get(:headless_examples_test_pid) do
        send(
          pid,
          {:invoke_runtime_tool, context.tenant_ref.id, tool_role_ref, operation_role_ref, attrs,
           opts}
        )
      end

      output = ~s({"data":{"viewer":{"id":"usr-linear-viewer"}}})

      result = %{
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
      }

      {:ok, Map.merge(result, authority_handoff("graphql-execute"))}
    end

    defp publication_authority_handoff(%{capability_id: "linear.issues.update"}),
      do: authority_handoff("issues-update")

    defp publication_authority_handoff(%{capability_id: "linear.comments.update"}),
      do: authority_handoff("comments-update")

    defp publication_authority_handoff(%{capability_id: "linear.comments.create"}),
      do: authority_handoff("comments-create")

    defp publication_authority_handoff(_receipt), do: %{}

    defp authority_handoff(operation_slug) do
      %{
        authority_authorized?: true,
        authority_handoff_ref: "authority-handoff://linear/#{operation_slug}",
        authority_packet_ref: "authority-packet://linear/#{operation_slug}",
        connector_binding_ref: "connector-binding://linear/primary",
        credential_lease_ref: "credential-lease://linear/primary",
        authority_raw_material_present?: false
      }
    end
  end

  defmodule GenericRuntimeBackend do
    def invoke_runtime_operation(context, runtime_role_ref, operation_role_ref, request, opts)
        when runtime_role_ref == :coding_agent_runtime and operation_role_ref == :session_turn do
      CodexAgentBackend.start_agent_run(context, request, opts)
    end

    def invoke_runtime_tool(context, tool_role_ref, operation_role_ref, attrs, opts) do
      SourceBackend.invoke_runtime_tool(context, tool_role_ref, operation_role_ref, attrs, opts)
    end

    def collect_evidence(context, evidence_role_ref, attrs, opts) do
      GitHubEvidenceBackend.collect_evidence(context, evidence_role_ref, attrs, opts)
    end

    def invoke_resource_effect(context, resource_effect_role_ref, attrs, opts) do
      GitHubEvidenceBackend.invoke_resource_effect(context, resource_effect_role_ref, attrs, opts)
    end
  end
end
