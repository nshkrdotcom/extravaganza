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
    assert live_guide =~ "## Structured Logs"
    assert live_guide =~ "mix extravaganza.headless.logs --json --logs-root"
    assert live_guide =~ "headless_runtime_logs.v1"
    assert live_guide =~ "`startup.terminal_cleanup.completed`"
    assert live_guide =~ "Log presenters redact secret-like fields"
    assert live_guide =~ "## Operator Dashboard Replacement"
    assert live_guide =~ "`operator_dashboard` projection"
    assert live_guide =~ "tokens-per-second throughput"
    assert live_guide =~ "open http://localhost:4000/operator-console"
    assert live_guide =~ "curl http://localhost:4000/api/v1/events"
    assert live_guide =~ "## Live Dashboard Updates"
    assert live_guide =~ "headless_observability_update.v1"
    assert live_guide =~ "`/operator-console/updates`"
    assert live_guide =~ "`live_provider_receipt`"
    assert live_guide =~ "## Symphony API Compatibility"
    assert live_guide =~ "`GET /api/v1/:issue_identifier`"
    assert live_guide =~ "`observability_issue`"
    assert live_guide =~ "`observability_refresh`"
    assert live_guide =~ "## Optional HTTP Port"
    assert live_guide =~ "mix extravaganza.headless.web --port 4001 --json"
    assert live_guide =~ "`server.port`"
    assert live_guide =~ "`GET /operator-console`"
    assert live_guide =~ "## Static Asset Replacement"
    assert live_guide =~ "`SymphonyElixirWeb.StaticAssets`"
    assert live_guide =~ "`/dashboard.css`"
    assert live_guide =~ "`/operator-console/updates`"
    assert live_guide =~ "ExtravaganzaWeb.static_paths() == []"

    assert credentials_guide =~
             "~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_source --live-product-path --json"

    assert credentials_guide =~
             "~/scripts/with_bash_secrets mix extravaganza.headless.live.codex_turn --live-product-path --json"

    assert credentials_guide =~
             "~/scripts/with_bash_secrets mix extravaganza.headless.live.github_evidence --live-product-path --json"
  end

  test "provider acceptance docs enumerate live commands, side effects, object ids, and evidence" do
    credentials_guide_path =
      Path.expand("../../../guides/headless_provider_credentials.md", __DIR__)

    assert {:ok, guide} = File.read(credentials_guide_path)

    for fragment <- [
          "## Provider Acceptance Matrix",
          "live.linear-source",
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_source --live-product-path --json",
          "`LINEAR_API_KEY`",
          "`--source-states`",
          "`--project-slug`",
          "`--team-id`",
          "`--assignee`",
          "`linear.issues.list`",
          "`subjects[].provider_external_ref`",
          "`subjects[].source_ref`",
          "`viewer_lower_request_ref`",
          "live.linear-current-states",
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_current_states --live-product-path --json --issue-ids",
          "`requested_issue_ids`",
          "`missing_issue_ids`",
          "`current_state_count`",
          "live.codex-turn",
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.codex_turn --live-product-path --json",
          "`OPENAI_API_KEY`",
          "`CODEX_API_KEY`",
          "`codex.session.turn`",
          "`run_ref`",
          "`workflow_ref`",
          "`session_ref`",
          "`turn_ref`",
          "`provider_session_id`",
          "`provider_turn_id`",
          "`event_stream_confirmed?`",
          "`token_accounting_confirmed?`",
          "`session_stop_confirmed?`",
          "live.linear-publication",
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_publication --live-product-path --json --issue-id",
          "`--comment-id`",
          "`--message`",
          "`--state-name`",
          "`linear.comments.create`",
          "`linear.comments.update`",
          "`linear.issues.update`",
          "`source_publication_ref`",
          "`comment_ref`",
          "`workpad_refs`",
          "`state_id`",
          "`state_name`",
          "live.linear-graphql-tool",
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_graphql_tool --live-product-path --json --query",
          "`--variables-json`",
          "`linear.graphql.execute`",
          "`tool_name`",
          "`dynamic_tool_response`",
          "live.github-evidence",
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.github_evidence --live-product-path --json --repo",
          "`GH_TOKEN`",
          "`GITHUB_TOKEN`",
          "`github.pr.evidence`",
          "`pull_number`",
          "`head_sha`",
          "`evidence_ref`",
          "`provider_refs`",
          "`receipt_refs`",
          "`operation_receipts`",
          "live.smoke",
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.smoke --live-product-path --json",
          "`required_operations`",
          "`completed_operations`",
          "`provider_effect_count`",
          "`all_provider_effects_completed?`",
          "`authority_handoff_ref`",
          "`authority_packet_ref`",
          "`connector_binding_ref`",
          "`credential_lease_ref`",
          "`lower_request_ref`",
          "`lower_receipt_ref`",
          "`product_readback_confirmed?`",
          "`provider_request_sent?`",
          "`provider_response_received?`",
          "`receipt_recorded?`"
        ] do
      assert guide =~ fragment
    end
  end
end
