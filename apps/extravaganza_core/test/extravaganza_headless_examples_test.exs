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
             :evidence,
             :events,
             :smoke
           ]
  end

  test "live Linear source example skips explicitly without a supplied credential" do
    output =
      capture_io(fn ->
        assert :ok = HeadlessCLI.run(:live_linear_source, ["--json", "--trace-id", "trace:live"])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "live.linear-source"
    assert decoded["data"]["status"] == "skipped"

    assert decoded["data"]["skip_reason"] == %{
             "code" => "missing_credential",
             "credential_ref" => "LINEAR_API_KEY"
           }

    refute String.contains?(output, "env-linear")
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
          "scripts/headless/live_linear_source.exs"
        ] do
      assert File.regular?(Path.join(root, path))
    end
  end

  defp common_args,
    do: ["--json", "--fixture", "headless_m1", "--trace-id", "trace:examples"]
end
