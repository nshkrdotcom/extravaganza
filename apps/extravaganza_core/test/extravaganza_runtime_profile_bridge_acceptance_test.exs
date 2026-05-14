defmodule Extravaganza.RuntimeProfileBridgeAcceptanceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Extravaganza.HeadlessCLI

  @guardrails_ack "--ack-headless-guardrails"
  @secret "linear-runtime-profile-secret"

  setup do
    previous_runtime_backend = Application.get_env(:app_kit_core, :runtime_backend)
    previous_fixture_context = Application.get_env(:extravaganza_core, :headless_fixture_context?)

    Application.delete_env(:app_kit_core, :runtime_backend)
    Application.delete_env(:extravaganza_core, :headless_fixture_context?)

    on_exit(fn ->
      restore_env(:app_kit_core, :runtime_backend, previous_runtime_backend)
      restore_env(:extravaganza_core, :headless_fixture_context?, previous_fixture_context)
    end)
  end

  @tag :tmp_dir
  test "profile reload applies imported runtime profile through the real AppKit Mezzanine bridge",
       %{tmp_dir: tmp_dir} do
    workflow_path = write_workflow!(tmp_dir)
    cache_path = Path.join(tmp_dir, "last-good-profile.json")
    unique = :erlang.unique_integer([:positive])
    tenant_id = "extravaganza-runtime-profile-#{unique}"

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
                   "--tenant-id",
                   tenant_id,
                   "--pack-version",
                   "1.0.0-runtime-profile-#{unique}",
                   "--trace-id",
                   "trace:runtime-profile-bridge"
                 ])
      end)

    decoded = Jason.decode!(output)

    assert decoded["ok"] == true
    assert decoded["operation"] == "profile_reload"
    assert decoded["data"]["status"] == "reloaded"

    assert decoded["data"]["profile"]["app_kit_runtime_profile"]["policy_bundle"]["policy_kind"] ==
             "workflow_md"

    apply_readback = decoded["data"]["runtime_profile_apply"]

    assert apply_readback["status"] == "updated"
    assert apply_readback["tenant_ref"] == tenant_id
    assert apply_readback["profile_ref"] == "runtime-profile://symphony-workflow"
    assert apply_readback["program_ref"] =~ "program://"
    assert apply_readback["policy_bundle_ref"] =~ "policy-bundle://"
    assert apply_readback["work_class_ref"] =~ "work-class://"
    assert apply_readback["placement_profile_ref"] =~ "placement-profile://"
    assert decoded["runtime_profile_ref"] == "runtime-profile://symphony-workflow"
    refute output =~ @secret
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
      active_states:
        - Ready
      terminal_states:
        - Done
    codex:
      command: codex app-server
    workspace:
      root: runtime-profile-workspaces
    ---
    Ship {{ issue.identifier }}
    """)

    path
  end
end
