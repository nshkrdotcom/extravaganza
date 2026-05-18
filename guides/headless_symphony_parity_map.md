# Symphony Headless Parity Map

Purpose: document how Extravaganza implements the Symphony-style headless
coding-agent product surface through Mix tasks, the Phoenix/API surface,
scripts, examples, and live provider proofs.

This is a current product-surface map. It is not a stale gap list. Items marked
partial are intentional product-surface choices or places where one surface
exists but another equivalent surface is not exposed.

## Scope and Evidence Anchors

Evidence anchors:

- Mix task inventory:
  `apps/extravaganza_core/lib/mix/tasks/extravaganza.headless.ex`
- CLI parser and dispatch:
  `apps/extravaganza_core/lib/extravaganza/headless_cli.ex`
- Product host facade:
  `apps/extravaganza_core/lib/extravaganza/product_host.ex`
- Headless programmatic surface:
  `apps/extravaganza_core/lib/extravaganza/headless_surface.ex`
- Live provider examples:
  `apps/extravaganza_core/lib/extravaganza/headless_live_examples.ex`
- HTTP routes:
  `apps/extravaganza_web/lib/extravaganza_web/router.ex`
- API controller:
  `apps/extravaganza_web/lib/extravaganza_web/controllers/api/headless_controller.ex`
- Scripts and examples:
  `scripts/headless/*.exs` and `examples/headless/*.json`
- Verification guide:
  `guides/headless_full_functionality_verification.md`

Status legend:

- **Done**: implemented and reachable through a supported product path.
- **Partial**: supported through one product path, but not exposed through every
  possible command/API/browser equivalent.
- **Out of scope**: intentionally not part of the Extravaganza product surface.

## Current Surface Matrix

| Behavior | Mix command | HTTP/browser/API surface | Script/example | Status |
| --- | --- | --- | --- | --- |
| Optional web shell with CLI `--port` and workflow `server.port` | `mix extravaganza.headless.web --port 4001 --json` and `--once` plan mode | Starts Phoenix endpoint and exposes browser/API routes | Covered by `headless_server_test.exs` | Done |
| Browser home/dashboard | N/A | `GET /`, `GET /queue`, `GET /operator-console` | Browser tests and web shell proof | Done |
| Operator update stream | N/A | `GET /operator-console/updates` | SSE route covered by web tests | Done |
| State snapshot | `mix extravaganza.headless.state --json` | `GET /api/v1/state` | `scripts/headless/state.exs`, `examples/headless/state.json` | Done |
| Queue readback | `mix extravaganza.headless.queue --json` | `GET /queue`; queue is also represented in state projections. There is intentionally no `/api/v1/queue` route. | No dedicated queue script | Partial |
| Subject detail and issue compatibility lookup | `mix extravaganza.headless.subject SUBJECT_ID --json` | `GET /subjects/:subject_id`, `GET /api/v1/subjects/:subject_id`, `GET /api/v1/:issue_identifier` | API/controller tests | Done |
| Subject operator actions | `mix extravaganza.headless.control SUBJECT_ID ACTION --ack-headless-guardrails --json` | Browser/API `POST /subjects/:subject_id/actions/:action`; API compatibility `POST /api/v1/subjects/:subject_id/control/:action` | Covered by controller tests | Done |
| Read lease and stream attach lease | No direct Mix command | Browser/API `POST /subjects/:subject_id/read-lease` and `POST /subjects/:subject_id/stream-attach-lease` | Covered by controller tests | Partial |
| Refresh trigger | `mix extravaganza.headless.refresh --ack-headless-guardrails --json` | `POST /api/v1/refresh` | API/controller tests | Done |
| Review listing and decisions | `mix extravaganza.headless.reviews --json`, `mix extravaganza.headless.review DECISION_ID --decision accept --ack-headless-guardrails --json` | Browser/API `GET /reviews`, `POST /reviews/:decision_id/decisions/:decision` | `scripts/headless/review_decision.exs` | Done |
| Run detail | `mix extravaganza.headless.run RUN_ID --json` | `GET /api/v1/runs/:run_id` | `scripts/headless/run_detail.exs`, `examples/headless/run.json` | Done |
| Evidence chain | `mix extravaganza.headless.evidence RUN_ID --json` | `GET /api/v1/runs/:run_id/evidence` | `scripts/headless/evidence_chain.exs`, `examples/headless/evidence.json` | Done |
| Event page | `mix extravaganza.headless.events RUN_ID --json` | `GET /api/v1/events` | `examples/headless/events.json` | Done |
| Source publication preview | `mix extravaganza.headless.source_preview SUBJECT_ID --json` | `GET /api/v1/subjects/:subject_id/source-publication` | Controller tests | Done |
| Governed source publication | `mix extravaganza.headless.source_publish SUBJECT_ID --ack-headless-guardrails --json` | `POST /api/v1/source-publication`, `POST /api/v1/subjects/:subject_id/source-publication` | `scripts/headless/source_publish.exs` | Done |
| Source sync/inbound issue shaping | `mix extravaganza.headless.source.sync --ack-headless-guardrails --json` and `mix extravaganza.headless.source_sync --ack-headless-guardrails --json` | `ProductHost.sync_issue_tracker_source/2` and `HeadlessSurface.sync_issue_tracker_source/2` | `scripts/headless/source_sync.exs` | Done |
| Runtime status/logs | `mix extravaganza.headless.status --json`, `mix extravaganza.headless.logs --json` | `GET /api/v1/status`, `GET /api/v1/logs` | `scripts/headless/status.exs`, `scripts/headless/logs.exs` | Done |
| Preflight and shutdown | `mix extravaganza.headless.preflight --json`, `mix extravaganza.headless.stop --confirm-no-active-lower-runs --ack-headless-guardrails --json` | `GET /api/v1/preflight`, `POST /api/v1/shutdown` | `scripts/headless/preflight.exs`, `scripts/headless/stop.exs` | Done |
| Symphony workflow profile import | `mix extravaganza.headless.profile --json`, `profile_validate`, `profile_reload` | `GET /api/v1/profile`, `POST /api/v1/profile/validate`, `POST /api/v1/profile/reload` | `scripts/headless/profile_validate.exs`, `scripts/headless/profile_reload.exs` | Done |
| Start run command | `mix extravaganza.headless.start --ack-headless-guardrails --json`; fixture start uses `--fixture headless_m1` | Product host and browser surfaces use the same presenters/readbacks | `scripts/headless/assert_non_fixture_start.exs`, `scripts/headless/start_fixture_run.exs` | Done |
| Deterministic same-run proof | `MIX_ENV=test mix extravaganza.headless.smoke --deterministic --same-run --json` | `ProductHost.same_run_smoke/1` | StackLab external acceptance and deterministic command proof | Done |
| Live Linear source | `mix extravaganza.headless.live.linear_source --live-product-path --ack-headless-guardrails --json` | `POST /api/v1/live/linear-source` for API contract; real provider effects verified through Mix task | `scripts/headless/live_linear_source.exs` | Done |
| Live Linear current states | `mix extravaganza.headless.live.linear_current_states --live-product-path --ack-headless-guardrails --json --issue-id LINEAR_ISSUE_UUID` | `POST /api/v1/live/linear-current-states` for API contract | `scripts/headless/live_linear_current_states.exs` | Done |
| Live Codex turn | `mix extravaganza.headless.live.codex_turn --live-product-path --ack-headless-guardrails --json` | `POST /api/v1/live/codex-turn` for API contract | `scripts/headless/live_codex_turn.exs` | Done |
| Live Linear publication | `mix extravaganza.headless.live.linear_publication --live-product-path --ack-headless-guardrails --json --issue-id LINEAR_ISSUE_UUID` | `POST /api/v1/live/linear-publication` for API contract | `scripts/headless/live_linear_publication.exs` | Done |
| Live Linear GraphQL dynamic tool | `mix extravaganza.headless.live.linear_graphql_tool --live-product-path --ack-headless-guardrails --json --query "query Viewer { viewer { id } }"` | `POST /api/v1/live/linear-graphql-tool` for API contract | `scripts/headless/live_linear_graphql_tool.exs` | Done |
| Live GitHub evidence | `mix extravaganza.headless.live.github_evidence --live-product-path --ack-headless-guardrails --json --repo OWNER/REPO --pull-number PR_NUMBER --ref HEAD_SHA` | `POST /api/v1/live/github-evidence` for API contract | `scripts/headless/live_github_evidence.exs` | Done |
| Live GitHub PR cleanup | `mix extravaganza.headless.live.github_pr_cleanup --live-product-path --ack-headless-guardrails --json --repo OWNER/REPO --branch DISPOSABLE_BRANCH --confirm-close` | `POST /api/v1/live/github-pr-cleanup` for API contract | `scripts/headless/live_github_pr_cleanup.exs` | Done |
| Aggregate live smoke | `mix extravaganza.headless.live.smoke --live-product-path --ack-headless-guardrails --json --api-key-stdin ...` | `POST /api/v1/live/smoke` for API contract | `scripts/headless/live_smoke.exs` | Done |
| Static asset compatibility routes from Symphony's old dashboard implementation | N/A | N/A; Extravaganza renders product-owned Phoenix templates and SSE updates | N/A | Out of scope |
| Direct lower runtime/provider module access from product code | N/A | N/A | Enforced by no-bypass/static tests | Out of scope |

## Live API Route Posture

HTTP live routes are part of the product API contract. They require
`ack_headless_guardrails=true` or `guardrails_ack=true`, reject raw credential
params, and accept refs/flags such as `connection_id`, `credential_ref`,
`credential_lease_ref`, `live_product_path`, `repo`, `pull_number`, `ref`,
`issue_id`, `issue_ids`, `query`, and `variables_json`.

Real provider credential injection for local verification is intentionally
exercised through the Mix task surface with `~/scripts/with_bash_secrets`, not
through raw HTTP credential params.

## Script Inventory

Current public scripts:

- `scripts/headless/assert_non_fixture_start.exs`
- `scripts/headless/state.exs`
- `scripts/headless/start_fixture_run.exs`
- `scripts/headless/run_detail.exs`
- `scripts/headless/evidence_chain.exs`
- `scripts/headless/review_decision.exs`
- `scripts/headless/source_sync.exs`
- `scripts/headless/source_publish.exs`
- `scripts/headless/status.exs`
- `scripts/headless/logs.exs`
- `scripts/headless/preflight.exs`
- `scripts/headless/profile_validate.exs`
- `scripts/headless/profile_reload.exs`
- `scripts/headless/stop.exs`
- `scripts/headless/live_linear_source.exs`
- `scripts/headless/live_linear_current_states.exs`
- `scripts/headless/live_codex_turn.exs`
- `scripts/headless/live_linear_publication.exs`
- `scripts/headless/live_linear_graphql_tool.exs`
- `scripts/headless/live_github_evidence.exs`
- `scripts/headless/live_github_pr_cleanup.exs`
- `scripts/headless/live_smoke.exs`

## Practical Verification Notes

Use `guides/headless_full_functionality_verification.md` for the full command
sequence. Current release verification must prove:

- deterministic Mix tasks and scripts return valid envelopes;
- browser/API routes and wrong-method/not-found errors are covered by tests;
- every live provider lane runs through `--live-product-path` with
  `~/scripts/with_bash_secrets`;
- GitHub cleanup is tested only against a disposable PR;
- output contains route evidence, authority refs, credential lease refs, lower
  request refs, lower receipt refs, and no raw secrets;
- `mix ci` is green before release.
