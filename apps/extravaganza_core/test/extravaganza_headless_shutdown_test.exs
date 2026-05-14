defmodule Extravaganza.HeadlessShutdownTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Extravaganza.{HeadlessCLI, HeadlessShutdown}

  setup do
    previous_headless_backend = Application.get_env(:app_kit_core, :headless_backend)
    previous_source_backend = Application.get_env(:app_kit_core, :source_backend)
    previous_fixture_context = Application.get_env(:extravaganza_core, :headless_fixture_context?)

    on_exit(fn ->
      restore_env(:app_kit_core, :headless_backend, previous_headless_backend)
      restore_env(:app_kit_core, :source_backend, previous_source_backend)
      restore_env(:extravaganza_core, :headless_fixture_context?, previous_fixture_context)
    end)
  end

  test "shutdown report renders offline status and proves no active lower runs" do
    assert {:ok, report} =
             HeadlessShutdown.run(
               confirm_no_active_lower_runs?: true,
               trace_id: "trace:shutdown-test",
               reason: "phase92"
             )

    assert report["schema_ref"] == "headless_shutdown.v1"
    assert report["replacement_for"] == "symphony_application_stop_offline_status"
    assert report["status"] == "offline"
    assert report["offline_status"]["app_status"] == "offline"
    assert report["offline_status"]["terminal_line"] == "app_status=offline"
    assert report["offline_status"]["event"]["event_kind"] == "runtime.offline"
    assert report["offline_status"]["event"]["trace_id"] == "trace:shutdown-test"

    assert report["lower_run_posture"]["status"] == "no_active_lower_runs"
    assert report["lower_run_posture"]["active_lower_run_count"] == 0
    assert report["orphan_prevention"]["orphaned_lower_runs?"] == false
    assert report["orphan_prevention"]["verdict"] == "safe_to_stop"

    assert "mix extravaganza.headless.stop" in report["product_exposure"]
    assert "POST /api/v1/shutdown" in report["product_exposure"]
  end

  test "shutdown blocks instead of rendering offline when active lower runs are present" do
    assert {:error, {:active_lower_runs_present, report}} =
             HeadlessShutdown.run(
               active_lower_run_refs: ["lower-run://fixture/1", "lower-run://fixture/2"],
               trace_id: "trace:shutdown-blocked"
             )

    assert report["status"] == "blocked_active_lower_runs"
    assert report["offline_status_rendered?"] == false
    assert report["lower_run_posture"]["active_lower_run_count"] == 2

    assert report["lower_run_posture"]["active_lower_run_refs"] == [
             "lower-run://fixture/1",
             "lower-run://fixture/2"
           ]

    assert report["orphan_prevention"]["orphaned_lower_runs?"] == false
    assert report["orphan_prevention"]["verdict"] == "shutdown_blocked"
  end

  test "CLI stop emits standard JSON and keeps secret and path material out of output" do
    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:stop, [
                   "--json",
                   "--fixture",
                   "headless_m1",
                   "--confirm-no-active-lower-runs",
                   "--trace-id",
                   "trace:shutdown-cli"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "stop"
    assert decoded["data"]["schema_ref"] == "headless_shutdown.v1"
    assert decoded["data"]["offline_status"]["app_status"] == "offline"
    assert decoded["data"]["orphan_prevention"]["verdict"] == "safe_to_stop"

    refute output =~ "linear-secret-value"
    refute output =~ "/home/"
  end

  test "CLI stop returns standard error when lower-run posture is missing" do
    output =
      capture_io(fn ->
        assert :ok =
                 HeadlessCLI.run(:stop, [
                   "--json",
                   "--fixture",
                   "headless_m1",
                   "--trace-id",
                   "trace:shutdown-missing-posture"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == false
    assert decoded["operation"] == "stop"
    assert decoded["error"]["code"] == "lower_run_posture_required"
    assert decoded["error"]["missing_refs"] == ["lower_run_posture"]
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
