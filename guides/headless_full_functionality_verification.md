# Headless Full Functionality Verification

This guide is the operator checklist for proving the complete Extravaganza
headless product surface. It complements `guides/headless_api_reference.md` and
`guides/headless_provider_credentials.md` by grouping the commands into the
order used for release verification.

Run commands from the repo root:

```bash
cd /home/home/p/g/n/extravaganza
```

Live provider commands on the shared workstation must be prepended with
`~/scripts/with_bash_secrets`. The wrapper injects local shell credentials for
that process; product code must not print raw provider secrets.

## Deterministic Mix Task Proof

Run deterministic release proof under test env so fixture-safe AppKit and
ConfigRegistry test configuration are used:

```bash
export MIX_ENV=test
```

All of these commands should return an `extravaganza.headless.response.v1`
envelope with `ok: true`.

```bash
mix extravaganza.headless.state --fixture headless_m1 --json
mix extravaganza.headless.queue --fixture headless_m1 --json
mix extravaganza.headless.subject subject:fixture --fixture headless_m1 --json
mix extravaganza.headless.run run:fixture --fixture headless_m1 --json
mix extravaganza.headless.reviews --fixture headless_m1 --json
mix extravaganza.headless.source_preview subject:fixture --fixture headless_m1 --json
mix extravaganza.headless.profile --workflow WORKFLOW.md --env LINEAR_API_KEY=fixture-linear-key --json
mix extravaganza.headless.status --fixture headless_m1 --json
mix extravaganza.headless.logs --fixture headless_m1 --json
mix extravaganza.headless.preflight --json --skip-app-start --temporal-status reachable
mix extravaganza.headless.evidence run:fixture --fixture headless_m1 --json
mix extravaganza.headless.events run:fixture --fixture headless_m1 --json
mix extravaganza.headless.smoke --deterministic --same-run --json
mix extravaganza.headless.web --port 0 --json --once
mix extravaganza.headless.specs.check
```

Mutating product commands require explicit guardrail acknowledgement:

```bash
mix extravaganza.headless.start --json --fixture headless_m1
mix extravaganza.headless.refresh --fixture headless_m1 --ack-headless-guardrails --json
mix extravaganza.headless.control subject:fixture retry --fixture headless_m1 --ack-headless-guardrails --json
mix extravaganza.headless.review decision:fixture --decision accept --fixture headless_m1 --ack-headless-guardrails --json
mix extravaganza.headless.source.sync --ack-headless-guardrails --json
mix extravaganza.headless.source_sync --ack-headless-guardrails --json
mix extravaganza.headless.source_publish subject:fixture --fixture headless_m1 --ack-headless-guardrails --json
mix extravaganza.headless.profile_validate --workflow WORKFLOW.md --env LINEAR_API_KEY=fixture-linear-key --json
mix extravaganza.headless.profile_reload --fixture headless_m1 --workflow WORKFLOW.md --env LINEAR_API_KEY=fixture-linear-key --ack-headless-guardrails --json
mix extravaganza.headless.stop --fixture headless_m1 --confirm-no-active-lower-runs --ack-headless-guardrails --json
```

The deterministic smoke proof should also be run under test env before release:

```bash
MIX_ENV=test mix extravaganza.headless.smoke --deterministic --same-run --json
```

## Script Proof

Keep `MIX_ENV=test` for deterministic script verification.

Scripts are public onboarding wrappers. Deterministic scripts should return the
same envelope family as the matching Mix task:

```bash
mix run --no-start scripts/headless/state.exs -- --json
mix run --no-start scripts/headless/start_fixture_run.exs -- --json
mix run --no-start scripts/headless/assert_non_fixture_start.exs
mix run --no-start scripts/headless/run_detail.exs -- --json
mix run --no-start scripts/headless/evidence_chain.exs -- --json
mix run --no-start scripts/headless/review_decision.exs -- --json
mix run --no-start scripts/headless/source_sync.exs -- --json
mix run --no-start scripts/headless/source_publish.exs -- --json
mix run --no-start scripts/headless/status.exs -- --json
mix run --no-start scripts/headless/logs.exs -- --json
mix run --no-start scripts/headless/preflight.exs -- --json --skip-app-start --temporal-status reachable
mix run --no-start scripts/headless/profile_validate.exs -- --json
mix run --no-start scripts/headless/profile_reload.exs -- --json
mix run --no-start scripts/headless/stop.exs -- --json
```

Live scripts can be run in deterministic fixture mode without credentials:

```bash
mix run --no-start scripts/headless/live_linear_source.exs -- --json
mix run --no-start scripts/headless/live_linear_current_states.exs -- --json
mix run --no-start scripts/headless/live_codex_turn.exs -- --json
mix run --no-start scripts/headless/live_linear_publication.exs -- --json
mix run --no-start scripts/headless/live_linear_graphql_tool.exs -- --json
mix run --no-start scripts/headless/live_github_evidence.exs -- --json
mix run --no-start scripts/headless/live_github_pr_cleanup.exs -- --json
mix run --no-start scripts/headless/live_smoke.exs -- --json
```

Expected fixture-mode live script evidence:

- `example_mode: "deterministic_fixture"`
- `live_provider_effect?: false`
- provider effect status is `skipped`

## HTTP and Browser Proof

The browser/operator routes are:

- `GET /`
- `GET /queue`
- `GET /operator-console`
- `GET /subjects/:subject_id`
- `POST /subjects/:subject_id/actions/:action`
- `POST /subjects/:subject_id/read-lease`
- `POST /subjects/:subject_id/stream-attach-lease`
- `GET /reviews`
- `POST /reviews/:decision_id/decisions/:decision`
- `GET /operator-console/updates`

The JSON API routes are listed in `guides/headless_api_reference.md`. For a
release proof, run the focused web tests plus the web shell plan:

```bash
mix test apps/extravaganza_web/test/extravaganza_web/controllers/api_headless_controller_test.exs
mix test apps/extravaganza_web/test/extravaganza_web/controllers/api_headless_run_readback_controller_test.exs
mix test apps/extravaganza_web/test/extravaganza_web/headless_server_test.exs
mix extravaganza.headless.web --port 0 --json --once
```

HTTP live routes are part of the API contract:

- `POST /api/v1/live/linear-source`
- `POST /api/v1/live/linear-current-states`
- `POST /api/v1/live/codex-turn`
- `POST /api/v1/live/linear-publication`
- `POST /api/v1/live/linear-graphql-tool`
- `POST /api/v1/live/github-evidence`
- `POST /api/v1/live/github-pr-cleanup`
- `POST /api/v1/live/smoke`

They reject raw credential params. Real provider effects are verified through
the Mix task surface below.

## Live Provider Proof

Do not carry `MIX_ENV=test` into live provider proof unless you are explicitly
testing the test configuration. Use the normal local env and the workstation
secret wrapper:

```bash
unset MIX_ENV
```

Use concrete provider targets. For Linear, pass an issue UUID. For GitHub
evidence, pass a repo, pull number, and head SHA/ref. For GitHub cleanup, create
a disposable branch and PR specifically for the cleanup proof.

```bash
~/scripts/with_bash_secrets bash -lc 'printf "%s" "$LINEAR_API_KEY" | mix extravaganza.headless.live.linear_source --live-product-path --ack-headless-guardrails --json --api-key-stdin'
~/scripts/with_bash_secrets bash -lc 'printf "%s" "$LINEAR_API_KEY" | mix extravaganza.headless.live.linear_current_states --live-product-path --ack-headless-guardrails --json --api-key-stdin --issue-id LINEAR_ISSUE_UUID'
~/scripts/with_bash_secrets mix extravaganza.headless.live.codex_turn --live-product-path --ack-headless-guardrails --json
~/scripts/with_bash_secrets bash -lc 'printf "%s" "$LINEAR_API_KEY" | mix extravaganza.headless.live.linear_publication --live-product-path --ack-headless-guardrails --json --api-key-stdin --issue-id LINEAR_ISSUE_UUID --message "Extravaganza live publication proof"'
~/scripts/with_bash_secrets bash -lc 'printf "%s" "$LINEAR_API_KEY" | mix extravaganza.headless.live.linear_graphql_tool --live-product-path --ack-headless-guardrails --json --api-key-stdin --query "query Viewer { viewer { id } }" --variables-json "{}"'
~/scripts/with_bash_secrets mix extravaganza.headless.live.github_evidence --live-product-path --ack-headless-guardrails --json --repo OWNER/REPO --pull-number PR_NUMBER --ref HEAD_SHA
~/scripts/with_bash_secrets mix extravaganza.headless.live.github_pr_cleanup --live-product-path --ack-headless-guardrails --json --repo OWNER/REPO --branch DISPOSABLE_BRANCH --confirm-close --closing-comment "Extravaganza cleanup proof"
~/scripts/with_bash_secrets bash -lc 'printf "%s" "$LINEAR_API_KEY" | mix extravaganza.headless.live.smoke --live-product-path --ack-headless-guardrails --json --api-key-stdin --assignee all --issue-id LINEAR_ISSUE_UUID --issue-ids LINEAR_ISSUE_UUID --repo OWNER/REPO --pull-number PR_NUMBER --ref HEAD_SHA'
```

Every completed live lane should show:

- `example_mode: "live_product_path"`
- `live_provider_effect?: true`
- `credential_preflight.status: "dispatchable"`
- `provider_request_sent?: true`
- `provider_response_received?: true`
- `receipt_recorded?: true`
- `product_readback_confirmed?: true`
- route evidence with product role, binding, manifest, authority, credential
  lease, lower request, lower receipt, projection/evidence, and trace refs

After capturing live output, scan the evidence for secret-like strings before
committing it. Do not commit raw provider responses or raw credentials.

## Static Safety and Final QC

Run these before calling the product verified:

```bash
mix test apps/extravaganza_core/test/extravaganza_provider_impl_api_static_test.exs
mix test apps/extravaganza_core/test/extravaganza_runtime_env_api_static_test.exs
mix test apps/extravaganza_core/test/extravaganza_runtime_decoupling_test.exs
mix test apps/extravaganza_core/test/extravaganza_headless_json_contract_test.exs
mix test apps/extravaganza_core/test/extravaganza_headless_docs_test.exs
mix ci
```

Cross-repo static scanners should also be run from StackLab when changing
generic-stack behavior:

```bash
cd /home/home/p/g/n/stack_lab
mix stack_lab.no_regular_expression.scan --all-target-repos --summary
mix stack_lab.dynamic_atom.scan --all-target-repos --summary
mix stack_lab.process_supervision.scan --all-target-repos --summary
```
