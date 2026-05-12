defmodule Extravaganza.HeadlessDocsTest do
  use ExUnit.Case, async: true

  test "Symphony workflow profile guide documents product and lower-layer mapping" do
    guide_path = Path.expand("../../../guides/headless_symphony_workflow_profiles.md", __DIR__)

    assert {:ok, guide} = File.read(guide_path)

    assert guide =~ "WORKFLOW.md"
    assert guide =~ "Extravaganza.SymphonyWorkflowImport"
    assert guide =~ "app_kit_runtime_profile"
    assert guide =~ "AppKit.InstallationSurface"
    assert guide =~ "runtime-profile service"
    assert guide =~ "Runtime/product code does not read ambient OS environment variables"
    assert guide =~ "profile_reload"
    assert guide =~ "AppKit.RuntimeSurface"
    assert guide =~ "AppKit.SourceSurface"
  end
end
