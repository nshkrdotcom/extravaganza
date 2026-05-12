defmodule Extravaganza.HeadlessExamplesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Extravaganza.{HeadlessCLI, HeadlessFixtureBackend}

  setup do
    previous_backend = Application.get_env(:app_kit_core, :headless_backend)
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

      if previous_source_backend do
        Application.put_env(:app_kit_core, :source_backend, previous_source_backend)
      else
        Application.delete_env(:app_kit_core, :source_backend)
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
             :live_codex_turn,
             :live_linear_publication,
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
          Mix.Tasks.Extravaganza.Headless.LiveCodexTurn,
          Mix.Tasks.Extravaganza.Headless.LiveLinearPublication,
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
          {"extravaganza.headless.live.codex_turn", "live.codex-turn",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live_codex_turn", "live.codex-turn",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live.linear_publication", "live.linear-publication",
           ["--json", "--trace-id", "trace:examples"]},
          {"extravaganza.headless.live_linear_publication", "live.linear-publication",
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

  @tag :live_provider
  test "live provider examples skip explicitly without supplied credentials but exercise product path" do
    for {operation, expected_operation, provider, credential_refs} <- [
          {:live_linear_source, "live.linear-source", "linear", ["LINEAR_API_KEY"]},
          {:live_codex_turn, "live.codex-turn", "codex", ["OPENAI_API_KEY", "CODEX_API_KEY"]},
          {:live_linear_publication, "live.linear-publication", "linear", ["LINEAR_API_KEY"]},
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
      assert decoded["refs"]["source_publication_ref"] == "source-publication:fixture"
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
    refute output =~ secret
    refute output =~ "live_provider_effect_deferred"

    assert_received {:fetch_linear_candidates, "extravaganza", source_binding, _opts}
    assert source_binding.source_binding_id == "linear-primary"
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
    assert decoded["data"]["product_path"]["appkit_surfaces"] == ["AppKit.HeadlessSurface"]
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
             "live.linear-publication",
             "live.linear-source"
           ]

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
          "scripts/headless/live_codex_turn.exs",
          "scripts/headless/live_linear_publication.exs",
          "scripts/headless/live_github_evidence.exs",
          "scripts/headless/live_smoke.exs"
        ] do
      assert File.regular?(Path.join(root, path))
    end
  end

  defp common_args,
    do: ["--json", "--fixture", "headless_m1", "--trace-id", "trace:examples"]

  defmodule SourceBackend do
    @behaviour AppKit.Core.Backends.SourceBackend

    @impl true
    def sync_linear_issues(_context, _source_page, _opts), do: {:ok, %{}}

    @impl true
    def current_linear_issue_states(_context, issue_ids, _source_binding, _opts) do
      {:ok, %{requested_issue_ids: issue_ids, missing_issue_ids: []}}
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
         lower_request_ref: "lower-request://linear/source",
         lower_receipt_ref: "lower-receipt://linear/source"
       }}
    end

    @impl true
    def publish_linear_source(context, attrs, opts) do
      if pid = Process.get(:headless_examples_test_pid) do
        send(pid, {:publish_linear_source, context.tenant_ref.id, attrs, opts})
      end

      {:ok,
       %{
         source_publication_receipt: %{
           source_publication_receipt_ref: "source-publication://linear-primary/test",
           source_publish_ref: attrs.source_publish_ref,
           source_binding_id: attrs.source_binding_id,
           source_ref: attrs.source_ref,
           status: "published",
           capability_id: "linear.comments.create",
           lower_request_ref: "lower-request://linear/publication",
           lower_receipt_ref: "lower-receipt://linear/publication",
           workpad_refs: ["linear-comment://comment-1"]
         },
         provider_request_sent?: true,
         provider_response_received?: true
       }}
    end
  end
end
