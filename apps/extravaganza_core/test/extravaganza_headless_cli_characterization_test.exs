defmodule Extravaganza.HeadlessCLICharacterizationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Extravaganza.{HeadlessCLI, HeadlessFixtureBackend}

  @guardrails_ack "--ack-headless-guardrails"
  @legacy_guardrails_ack "--i-understand-that-this-will-be-running-without-the-usual-guardrails"

  setup do
    previous_backend = Application.get_env(:app_kit_core, :headless_backend)
    previous_source_backend = Application.get_env(:app_kit_core, :source_backend)
    previous_runtime_backend = Application.get_env(:app_kit_core, :runtime_backend)
    previous_fixture_context = Application.get_env(:extravaganza_core, :headless_fixture_context?)

    Application.put_env(:app_kit_core, :headless_backend, HeadlessFixtureBackend)
    Application.put_env(:app_kit_core, :source_backend, HeadlessFixtureBackend)
    Application.put_env(:app_kit_core, :runtime_backend, HeadlessFixtureBackend)
    Application.put_env(:extravaganza_core, :headless_fixture_context?, true)

    on_exit(fn ->
      restore_env(:app_kit_core, :headless_backend, previous_backend)
      restore_env(:app_kit_core, :source_backend, previous_source_backend)
      restore_env(:app_kit_core, :runtime_backend, previous_runtime_backend)
      restore_env(:extravaganza_core, :headless_fixture_context?, previous_fixture_context)
    end)
  end

  test "operation metadata freezes the current CLI registry and public Mix task names" do
    specs = HeadlessCLI.operation_specs()
    operations = Enum.map(specs, & &1.operation)
    task_names = specs |> Enum.flat_map(& &1.mix_tasks) |> Enum.sort()

    assert operations == HeadlessCLI.operations()

    assert operations == [
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

    assert task_names == Enum.uniq(task_names)

    for task_name <- task_names do
      assert is_atom(Mix.Task.get(task_name))
    end
  end

  test "parser keeps every current CLI flag in an explicit option field" do
    opts =
      HeadlessCLI.parse_options([
        "--json",
        "--pretty",
        "--fixture",
        "headless_m1",
        "--trace-id",
        "trace:parse",
        "--tenant-id",
        "tenant-1",
        "--pack-version",
        "pack-1",
        "--workflow-path",
        "workflow.yml",
        "--cwd",
        "/tmp/extravaganza",
        "--logs-root",
        "logs",
        "--skip-app-start",
        "--temporal-status",
        "reachable",
        "--source-binding-ref",
        "linear-primary",
        "--source-binding-refs",
        "linear-secondary,linear-tertiary",
        "--credential-refs",
        "LINEAR_API_KEY,GH_TOKEN",
        "--confirm-no-active-lower-runs",
        "--active-lower-run-ref",
        "lower-1",
        "--active-lower-run-refs",
        "lower-2,lower-3",
        "--profile-cache",
        "profile-cache.json",
        "--env",
        "A=B",
        "--env",
        "C=D",
        "--run-id",
        "run-1",
        "--subject-id",
        "subject-1",
        "--issue-id",
        "issue-1",
        "--issue-ids",
        "issue-2,issue-3",
        "--comment-id",
        "comment-1",
        "--state-id",
        "state-1",
        "--state-name",
        "In Progress",
        "--source-state",
        "Todo",
        "--source-states",
        "Done,Backlog",
        "--project-slug",
        "project-1",
        "--team-id",
        "team-1",
        "--assignee",
        "me",
        "--allow-create-fallback",
        "--no-create-fallback",
        "--dry-run",
        "--query",
        "query Viewer { viewer { id } }",
        "--variables-json",
        "{}",
        "--repo",
        "nshkrdotcom/extravaganza",
        "--branch",
        "branch-1",
        "--pull-number",
        "123",
        "--ref",
        "sha-1",
        "--title",
        "Title",
        "--description",
        "Description",
        "--message",
        "Message",
        "--closing-comment",
        "Closing",
        "--effect",
        "comment",
        "--idempotency-key",
        "idem-1",
        "--cursor",
        "cursor-1",
        "--limit",
        "10",
        "--action",
        "retry",
        "--decision",
        "accept",
        "--reason",
        "because",
        "--deterministic",
        "--same-run",
        "--live-product-path",
        @guardrails_ack,
        @legacy_guardrails_ack,
        "--api-key-stdin",
        "--connection-id",
        "conn-1",
        "--credential-ref",
        "credential-1",
        "--credential-lease-ref",
        "lease-1",
        "--credential-available",
        "--confirm-close",
        "pos-1",
        "pos-2"
      ])

    assert opts.fixture == "headless_m1"
    assert opts.trace_id == "trace:parse"
    assert opts.tenant_id == "tenant-1"
    assert opts.pack_version == "pack-1"
    assert opts.workflow_path == "workflow.yml"
    assert opts.cwd == "/tmp/extravaganza"
    assert opts.logs_root == Path.expand("logs")
    assert opts.skip_app_start? == true
    assert opts.temporal_status == "reachable"
    assert opts.source_binding_refs == ["linear-secondary", "linear-tertiary", "linear-primary"]
    assert opts.credential_refs == ["LINEAR_API_KEY", "GH_TOKEN"]
    assert opts.confirm_no_active_lower_runs? == true
    assert opts.active_lower_run_refs == ["lower-2", "lower-3", "lower-1"]
    assert opts.profile_cache_path == "profile-cache.json"
    assert opts.env == %{"A" => "B", "C" => "D"}
    assert opts.run_id == "run-1"
    assert opts.subject_id == "subject-1"
    assert opts.issue_id == "issue-1"
    assert opts.issue_ids == ["issue-2", "issue-3"]
    assert opts.comment_id == "comment-1"
    assert opts.state_id == "state-1"
    assert opts.state_name == "In Progress"
    assert opts.source_state_names == ["Done", "Backlog", "Todo"]
    assert opts.project_slug == "project-1"
    assert opts.team_id == "team-1"
    assert opts.assignee == "me"
    assert opts.allow_create_fallback? == false
    assert opts.dry_run? == true
    assert opts.query == "query Viewer { viewer { id } }"
    assert opts.variables_json == "{}"
    assert opts.repo == "nshkrdotcom/extravaganza"
    assert opts.branch == "branch-1"
    assert opts.pull_number == "123"
    assert opts.ref == "sha-1"
    assert opts.title == "Title"
    assert opts.description == "Description"
    assert opts.message == "Message"
    assert opts.closing_comment == "Closing"
    assert opts.effect == "comment"
    assert opts.idempotency_key == "idem-1"
    assert opts.cursor == "cursor-1"
    assert opts.limit == "10"
    assert opts.action == "retry"
    assert opts.decision == "accept"
    assert opts.reason == "because"
    assert opts.deterministic? == true
    assert opts.same_run? == true
    assert opts.live_product_path? == true
    assert opts.guardrails_ack? == true
    assert opts.api_key_stdin? == true
    assert opts.connection_id == "conn-1"
    assert opts.credential_ref == "credential-1"
    assert opts.credential_lease_ref == "lease-1"
    assert opts.credential_available? == true
    assert opts.confirm_close? == true
    assert opts.positionals == ["pos-1", "pos-2"]
  end

  test "guardrail behavior is stable for every operation" do
    for spec <- HeadlessCLI.operation_specs() do
      operation = spec.operation

      assert HeadlessCLI.guardrails_acknowledgement_error(operation, fixture_args()) == nil

      product_args =
        if Map.get(spec, :live?, false),
          do: ["--json", "--live-product-path"],
          else: ["--json"]

      expected_guardrail? = Map.get(spec, :live?, false) or Map.get(spec, :mutating?, false)
      error = HeadlessCLI.guardrails_acknowledgement_error(operation, product_args)

      if expected_guardrail? do
        assert {:operator_ack_required, details} = error
        assert details.operation == spec.envelope_name
        assert details.required_flags == HeadlessCLI.guardrails_ack_flags()
      else
        assert error == nil
      end

      assert HeadlessCLI.guardrails_acknowledgement_error(
               operation,
               product_args ++ [@guardrails_ack]
             ) == nil
    end
  end

  test "fixture CLI context does not leak into concurrent non-fixture command context" do
    Application.delete_env(:app_kit_core, :headless_backend)
    Application.delete_env(:app_kit_core, :source_backend)
    Application.delete_env(:app_kit_core, :runtime_backend)
    Application.delete_env(:extravaganza_core, :headless_fixture_context?)

    fixture_task =
      Task.async(fn ->
        capture_io(fn ->
          assert :ok =
                   HeadlessCLI.run(:run, [
                     "--json",
                     "--fixture",
                     "headless_m1",
                     "--run-id",
                     "run:fixture",
                     "--trace-id",
                     "trace:fixture-context"
                   ])
        end)
      end)

    non_fixture_task =
      Task.async(fn ->
        capture_io(fn ->
          assert :ok =
                   HeadlessCLI.run(
                     :run,
                     [
                       "--json",
                       "--run-id",
                       "run:non-fixture",
                       "--trace-id",
                       "trace:non-fixture-context"
                     ],
                     headless_fixture_context?: true,
                     skip_bootstrap?: true,
                     headless_backend: __MODULE__.IsolatedHeadlessBackend
                   )
        end)
      end)

    fixture = fixture_task |> Task.await() |> Jason.decode!()
    non_fixture = non_fixture_task |> Task.await() |> Jason.decode!()

    assert fixture["ok"] == true
    assert fixture["refs"]["run_ref"] == "run:fixture"
    assert non_fixture["ok"] == false
    assert non_fixture["error"]["message"] =~ "isolated backend called"

    assert Application.get_env(:app_kit_core, :headless_backend) == nil
    assert Application.get_env(:app_kit_core, :source_backend) == nil
    assert Application.get_env(:app_kit_core, :runtime_backend) == nil
    assert Application.get_env(:extravaganza_core, :headless_fixture_context?) == nil
  end

  @tag :tmp_dir
  test "every operation emits the standard fixture JSON envelope shape", %{tmp_dir: tmp_dir} do
    for spec <- HeadlessCLI.operation_specs() do
      output =
        capture_io(fn ->
          assert :ok = HeadlessCLI.run(spec.operation, fixture_args(spec, tmp_dir))
        end)

      decoded = Jason.decode!(output)

      assert decoded["ok"] == true, "#{spec.operation} returned #{inspect(decoded)}"
      assert decoded["schema"] == "extravaganza.headless.response.v1"
      assert decoded["operation"] == spec.envelope_name
      assert decoded["trace_id"] == "trace:cli-characterization"
      assert is_binary(decoded["generated_at"])
      assert decoded["execution_route_ref"] == "generic_substrate:v1"
      assert is_map(decoded["refs"])
      assert Map.has_key?(decoded, "data")
    end
  end

  defp fixture_args(spec \\ %{}, tmp_dir \\ nil) do
    args = ["--json", "--fixture", "headless_m1", "--trace-id", "trace:cli-characterization"]

    args =
      if spec[:operation] in [:profile, :profile_validate, :profile_reload, :status] do
        args ++ workflow_args(tmp_dir)
      else
        args
      end

    if spec[:operation] == :stop do
      args ++ ["--confirm-no-active-lower-runs"]
    else
      args
    end
  end

  defp workflow_args(tmp_dir) when is_binary(tmp_dir) do
    workflow_path = Path.join(tmp_dir, "WORKFLOW.md")
    File.write!(workflow_path, valid_workflow())

    [
      "--workflow-path",
      workflow_path,
      "--env",
      "LINEAR_API_KEY=linear-secret-from-cli-characterization"
    ]
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
    agent:
      max_turns: 7
    codex:
      command: codex app-server
    hooks:
      timeout_ms: 12345
    ---
    Ship {{ issue.identifier }} on attempt {{ attempt }}
    """
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  defmodule IsolatedHeadlessBackend do
    @behaviour AppKit.Core.Backends.HeadlessBackend

    @impl true
    def state_snapshot(_context, _request, _opts), do: {:error, :isolated_backend_called}

    @impl true
    def runtime_subject_detail(_context, _subject_ref, _request, _opts),
      do: {:error, :isolated_backend_called}

    @impl true
    def runtime_run_detail(_context, _run_ref, _request, _opts),
      do: {:error, :isolated_backend_called}

    @impl true
    def request_runtime_refresh(_context, _request, _opts),
      do: {:error, :isolated_backend_called}

    @impl true
    def request_runtime_control(_context, _request, _opts),
      do: {:error, :isolated_backend_called}
  end
end
