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
    assert live_guide =~ "--ack-headless-guardrails"
    assert live_guide =~ "--i-understand-that-this-will-be-running-without-the-usual-guardrails"
    assert live_guide =~ "~/scripts/with_bash_secrets mix extravaganza.headless.live.smoke"
    assert live_guide =~ "mix extravaganza.headless.live.github_pr_cleanup"
    assert live_guide =~ "--confirm-close"
    assert live_guide =~ "not included in `live.smoke`"
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
             "~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_source --live-product-path --ack-headless-guardrails --json"

    assert credentials_guide =~
             "~/scripts/with_bash_secrets mix extravaganza.headless.live.codex_turn --live-product-path --ack-headless-guardrails --json"

    assert credentials_guide =~
             "~/scripts/with_bash_secrets mix extravaganza.headless.live.github_evidence --live-product-path --ack-headless-guardrails --json"

    assert credentials_guide =~
             "~/scripts/with_bash_secrets mix extravaganza.headless.live.github_pr_cleanup --live-product-path --ack-headless-guardrails --json --repo"
  end

  test "provider acceptance docs enumerate live commands, side effects, object ids, and evidence" do
    credentials_guide_path =
      Path.expand("../../../guides/headless_provider_credentials.md", __DIR__)

    assert {:ok, guide} = File.read(credentials_guide_path)

    for fragment <- [
          "## Provider Acceptance Matrix",
          "live.linear-source",
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_source --live-product-path --ack-headless-guardrails --json",
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
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_current_states --live-product-path --ack-headless-guardrails --json --issue-ids",
          "`requested_issue_ids`",
          "`missing_issue_ids`",
          "`current_state_count`",
          "live.codex-turn",
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.codex_turn --live-product-path --ack-headless-guardrails --json",
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
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_publication --live-product-path --ack-headless-guardrails --json --issue-id",
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
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_graphql_tool --live-product-path --ack-headless-guardrails --json --query",
          "`--variables-json`",
          "`linear.graphql.execute`",
          "`tool_name`",
          "`dynamic_tool_response`",
          "live.github-evidence",
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.github_evidence --live-product-path --ack-headless-guardrails --json --repo",
          "`GH_TOKEN`",
          "`GITHUB_TOKEN`",
          "`github.pr.evidence`",
          "`pull_number`",
          "`head_sha`",
          "`evidence_ref`",
          "`provider_refs`",
          "`receipt_refs`",
          "`operation_receipts`",
          "live.github-pr-cleanup",
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.github_pr_cleanup --live-product-path --ack-headless-guardrails --json --repo",
          "`--branch`",
          "`--confirm-close`",
          "`--closing-comment`",
          "`github.pr.list`",
          "`github.comment.create`",
          "`github.pr.update`",
          "`branch`",
          "`pull_numbers`",
          "`closed_pull_numbers`",
          "`write_operations`",
          "intentionally excluded from `live.smoke`",
          "live.smoke",
          "~/scripts/with_bash_secrets mix extravaganza.headless.live.smoke --live-product-path --ack-headless-guardrails --json",
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

  test "public headless API reference enumerates commands routes envelopes and errors" do
    api_reference_path = Path.expand("../../../guides/headless_api_reference.md", __DIR__)
    readme_path = Path.expand("../../../README.md", __DIR__)

    assert {:ok, guide} = File.read(api_reference_path)
    assert {:ok, readme} = File.read(readme_path)

    assert readme =~ "guides/headless_api_reference.md"

    for fragment <- [
          "# Headless API Reference",
          "## Command Reference",
          "## HTTP API Reference",
          "## Success Envelope",
          "## Error Envelope",
          "## Error Classes",
          "deterministic-only",
          "read-live",
          "write-live",
          "`mix extravaganza.headless.state --json`",
          "`mix extravaganza.headless.queue --json`",
          "`mix extravaganza.headless.subject SUBJECT_ID --json`",
          "`mix extravaganza.headless.run RUN_ID --json`",
          "`mix extravaganza.headless.start --ack-headless-guardrails --json`",
          "`mix extravaganza.headless.refresh --ack-headless-guardrails --json`",
          "`mix extravaganza.headless.control SUBJECT_ID ACTION --ack-headless-guardrails --json`",
          "`mix extravaganza.headless.reviews --json`",
          "`mix extravaganza.headless.review DECISION_ID --decision accept --ack-headless-guardrails --json`",
          "`mix extravaganza.headless.source_preview SUBJECT_ID --json`",
          "`mix extravaganza.headless.source.sync --json`",
          "`mix extravaganza.headless.source_sync --json`",
          "`mix extravaganza.headless.source_publish SUBJECT_ID --ack-headless-guardrails --json`",
          "`mix extravaganza.headless.profile --json`",
          "`mix extravaganza.headless.profile_validate --json`",
          "`mix extravaganza.headless.profile_reload --ack-headless-guardrails --json`",
          "`mix extravaganza.headless.status --json`",
          "`mix extravaganza.headless.logs --json`",
          "`mix extravaganza.headless.preflight --json --temporal-status reachable`",
          "`mix extravaganza.headless.evidence RUN_ID --json`",
          "`mix extravaganza.headless.events RUN_ID --json`",
          "`mix extravaganza.headless.smoke --deterministic --same-run --json`",
          "`mix extravaganza.headless.web --port 4000 --json`",
          "`mix extravaganza.headless.specs.check`",
          "`mix extravaganza.headless.live.linear_source --live-product-path --ack-headless-guardrails --json`",
          "`mix extravaganza.headless.live.linear_current_states --live-product-path --ack-headless-guardrails --json`",
          "`mix extravaganza.headless.live.codex_turn --live-product-path --ack-headless-guardrails --json`",
          "`mix extravaganza.headless.live.linear_publication --live-product-path --ack-headless-guardrails --json`",
          "`mix extravaganza.headless.live.linear_graphql_tool --live-product-path --ack-headless-guardrails --json`",
          "`mix extravaganza.headless.live.github_evidence --live-product-path --ack-headless-guardrails --json`",
          "`mix extravaganza.headless.live.github_pr_cleanup --live-product-path --ack-headless-guardrails --json --confirm-close`",
          "`mix extravaganza.headless.live.smoke --live-product-path --ack-headless-guardrails --json`",
          "`GET /api/v1/state`",
          "`GET /api/v1/status`",
          "`GET /api/v1/preflight`",
          "`GET /api/v1/logs`",
          "`GET /api/v1/profile`",
          "`POST /api/v1/profile/validate`",
          "`POST /api/v1/profile/reload`",
          "`POST /api/v1/source-publication`",
          "`POST /api/v1/live/linear-source`",
          "`POST /api/v1/live/linear-current-states`",
          "`POST /api/v1/live/codex-turn`",
          "`POST /api/v1/live/linear-publication`",
          "`POST /api/v1/live/linear-graphql-tool`",
          "`POST /api/v1/live/github-evidence`",
          "`POST /api/v1/live/github-pr-cleanup`",
          "`POST /api/v1/live/smoke`",
          "`GET /api/v1/subjects/:subject_id`",
          "`GET /api/v1/subjects/:subject_id/source-publication`",
          "`POST /api/v1/subjects/:subject_id/source-publication`",
          "`GET /api/v1/runs/:run_id`",
          "`GET /api/v1/runs/:run_id/evidence`",
          "`GET /api/v1/events`",
          "`POST /api/v1/refresh`",
          "`POST /api/v1/subjects/:subject_id/actions/:action`",
          "`POST /api/v1/subjects/:subject_id/control/:action`",
          "`POST /api/v1/subjects/:subject_id/read-lease`",
          "`POST /api/v1/subjects/:subject_id/stream-attach-lease`",
          "`GET /api/v1/reviews`",
          "`POST /api/v1/reviews/:decision_id/decisions/:decision`",
          "`GET /api/v1/:issue_identifier`",
          "`LINEAR_API_KEY`",
          "`OPENAI_API_KEY`",
          "`CODEX_API_KEY`",
          "`GH_TOKEN`",
          "`GITHUB_TOKEN`",
          "`ok`",
          "`schema`",
          "`operation`",
          "`trace_id`",
          "`idempotency_key`",
          "`runtime_profile_ref`",
          "`data`",
          "`refs`",
          "`warnings`",
          "`generated_at`",
          "`error.code`",
          "`error.class`",
          "`error.retryable?`",
          "`error.missing_refs`",
          "`missing_live_prerequisite`",
          "`missing_credential`",
          "`invalid_profile`",
          "`invalid_request`",
          "`provider_denial`",
          "`provider_error`",
          "`app_not_started`",
          "`product_host_unavailable`",
          "`operator_ack_required`",
          "`raw_provider_credential_param_not_supported`"
        ] do
      assert guide =~ fragment
    end
  end
end
