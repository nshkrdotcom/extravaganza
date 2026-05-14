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

  test "live provider docs distinguish deterministic fixtures from live product proofs" do
    live_guide_path = Path.expand("../../../guides/headless_live_demo.md", __DIR__)

    credentials_guide_path =
      Path.expand("../../../guides/headless_provider_credentials.md", __DIR__)

    assert {:ok, live_guide} = File.read(live_guide_path)
    assert {:ok, credentials_guide} = File.read(credentials_guide_path)

    assert live_guide =~ "deterministic fixture mode"
    assert live_guide =~ "live product path mode"
    assert live_guide =~ "--live-product-path"
    assert live_guide =~ "~/scripts/with_bash_secrets mix extravaganza.headless.live.smoke"

    assert credentials_guide =~
             "~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_source --live-product-path --json"

    assert credentials_guide =~
             "~/scripts/with_bash_secrets mix extravaganza.headless.live.codex_turn --live-product-path --json"

    assert credentials_guide =~
             "~/scripts/with_bash_secrets mix extravaganza.headless.live.github_evidence --live-product-path --json"
  end
end
