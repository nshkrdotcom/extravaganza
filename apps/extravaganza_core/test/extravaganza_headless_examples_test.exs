defmodule Extravaganza.HeadlessExamplesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Extravaganza.{HeadlessCLI, HeadlessFixtureBackend}

  setup do
    previous_backend = Application.get_env(:app_kit_core, :headless_backend)
    previous_fixture_context = Application.get_env(:extravaganza_core, :headless_fixture_context?)
    Application.put_env(:app_kit_core, :headless_backend, HeadlessFixtureBackend)
    Application.put_env(:extravaganza_core, :headless_fixture_context?, true)

    on_exit(fn ->
      if previous_backend do
        Application.put_env(:app_kit_core, :headless_backend, previous_backend)
      else
        Application.delete_env(:app_kit_core, :headless_backend)
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
end
