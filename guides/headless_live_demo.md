# Headless Live Demo Onboarding

Use this guide to run the full headless demo path end-to-end through the
Extravaganza product command surface, inspect JSON readbacks, and exercise live
provider examples.

## What you get out of the box

These are the user-facing headless entrypoints you can call today:

- Mix tasks (stable operator commands)
- REST API routes under `/api/v1/*` (shared presenter-backed envelopes)
- Example scripts under `scripts/headless/` for replayable command flows

The same command/result surface is used for both modes, but the output labels
them separately:

- deterministic fixture mode: CI-safe readbacks and fixture receipts; no live
  provider effect is dispatched.
- live product path mode: explicit `--live-product-path` execution through the
  product command path and governed lower providers.

## Preflight

From repo root:

```bash
cd /home/home/p/g/n/extravaganza
mix deps.get
```

Optional Temporal and lower-stack context (only needed for full live provider
verification):

```bash
cd /home/home/p/g/n/mezzanine
just dev-up
just dev-status
```

Set provider credentials in your shell before live runs:

- Linear example paths: `LINEAR_API_KEY`  
- Codex example paths: `OPENAI_API_KEY` and `CODEX_API_KEY`  
- GitHub example paths: `GH_TOKEN` or `GITHUB_TOKEN`

If needed for local ergonomics, linear examples also accept `--api-key-stdin`
for a piped credential.

Use `guides/headless_provider_credentials.md` for the full matrix and a repeatable
provider verification plan.

## Baseline verification (fixture path)

These should all pass before moving to live examples:

```bash
mix extravaganza.headless.start --json --fixture headless_m1
mix extravaganza.headless.state --json
mix extravaganza.headless.queue --json
mix extravaganza.headless.subject --json
mix extravaganza.headless.run run:fixture --json
mix extravaganza.headless.evidence run:fixture --json
mix extravaganza.headless.status --json
mix extravaganza.headless.logs --json
mix extravaganza.headless.source_publish subject:fixture --json
mix extravaganza.headless.profile_validate --workflow WORKFLOW.md --json
mix extravaganza.headless.profile_reload --workflow WORKFLOW.md --json
```

## Structured Logs

Extravaganza replaces Symphony's direct `LogFile.configure/default_log_file`
operator path with the product-owned `logs` command and `/api/v1/logs` read
surface. The command reads structured runtime logs through AppKit and returns
`headless_runtime_logs.v1` entries with event kind, timestamp, summary, issue
identity, issue identifier, session id, trace id, page metadata, and runtime
event payloads such as `runtime_profile_applied` and
`startup.terminal_cleanup.completed`.

The Symphony `--logs-root` behavior is preserved as a product command flag and
runtime-log request field. It selects the local/operator log root for the
readback request, but paths are redacted in command and API output:

```bash
mix extravaganza.headless.logs --json --logs-root tmp/extravaganza-logs
```

The same data is available from the API:

```bash
curl http://localhost:4000/api/v1/logs
```

Log presenters redact secret-like fields such as credentials, tokens,
authorization headers, passwords, private keys, and API keys, and they redact
absolute paths. Durable log storage and sink configuration remain AppKit/
Mezzanine runtime responsibilities; Extravaganza owns the product command,
request shape, API envelope, and operator documentation.

## Operator Dashboard Replacement

Extravaganza intentionally replaces Symphony's terminal `StatusDashboard` with
the product-owned `/operator-console` browser surface plus the same JSON
readbacks exposed by `/api/v1/state`, `/api/v1/status`, `/api/v1/events`, and
`/api/v1/logs`. The replacement dashboard is derived from AppKit runtime
readback through `StatePresenter.present/2`; the web layer does not query lower
stores, provider SDKs, or ambient OS environment variables.

The `operator_dashboard` projection in `headless_state_snapshot.v1` includes
the former terminal dashboard data: running, retrying, and completed counts;
running rows with session id, turn count, last event, last message, timestamp,
workspace summary, and token totals; retry rows with attempts, due times, and
errors; aggregate input, output, and total token counts; runtime seconds and
tokens-per-second throughput; Codex rate-limit summaries; polling and refresh
timing; and links to the queue, state, status, events, and logs surfaces.

Use the browser surface for operator scanning:

```bash
mix phx.server
open http://localhost:4000/operator-console
```

Use JSON when automating the same proof:

```bash
curl http://localhost:4000/api/v1/state
curl http://localhost:4000/api/v1/status
curl http://localhost:4000/api/v1/events
curl http://localhost:4000/api/v1/logs
```

## Live Dashboard Updates

Extravaganza replaces Symphony's `ObservabilityPubSub` and LiveView dashboard
refresh loop with a product-owned Phoenix PubSub fanout in the web shell. The
operator console opens `/operator-console/updates` as a server-sent event stream
and reloads its AppKit DTO dashboard when it receives
`headless_observability_update.v1`.

The update stream is emitted after product-owned command paths that can change
operator state:

- `POST /api/v1/refresh` emits `refresh_requested`.
- `POST /api/v1/subjects/:subject_id/control/:action` emits
  `run_status_change` when the command is accepted.
- `POST /api/v1/reviews/:decision_id/decisions/:decision` emits
  `review_decision` when the command is accepted.
- `POST /api/v1/source-publication` emits `live_provider_receipt` with
  `trigger: source_sync` after the AppKit source-publication surface records a
  provider receipt.

The envelope includes only safe metadata, refresh targets such as
`/operator-console`, `/api/v1/state`, `/api/v1/status`, `/api/v1/events`, and
`/api/v1/logs`, and no provider credentials or local workspace paths. The web
layer still reads dashboard data from AppKit presenters instead of lower stores
or provider SDKs.

## Static Asset Replacement

Symphony's optional Phoenix dashboard embedded static assets through
`SymphonyElixirWeb.StaticAssets` and served `/dashboard.css`,
`/vendor/phoenix_html/phoenix_html.js`, `/vendor/phoenix/phoenix.js`, and
`/vendor/phoenix_live_view/phoenix_live_view.js`. Those routes supported
Symphony's chosen dashboard implementation; they are not part of the required
headless runtime behavior.

Extravaganza does not port those asset routes. The product web shell keeps
`ExtravaganzaWeb.static_paths() == []` and renders the operator surface through
server-rendered Phoenix templates plus the explicit `/operator-console/updates`
SSE stream. The observability proof surface is the product route set:

- `GET /operator-console`
- `GET /operator-console/updates`
- `GET /api/v1/state`
- `GET /api/v1/status`
- `GET /api/v1/events`
- `GET /api/v1/logs`
- `POST /api/v1/refresh`

This preserves the headless dashboard/API behavior without requiring
Symphony-specific CSS or Phoenix vendor asset compatibility. If Extravaganza
adds bundled assets later, they should be product web assets only and should not
be treated as a lower runtime or provider dependency.

## Optional HTTP Port

Symphony's optional HTTP extension used CLI `--port` or workflow
`server.port` to start dashboard/API observability. Extravaganza replaces that
with the product-owned web shell command. CLI `--port` takes precedence over
workflow `server.port`, `0` requests an ephemeral OS-assigned port, and the
default bind host is loopback.

Print the resolved plan without starting Phoenix:

```bash
mix extravaganza.headless.web --port 4001 --json --once
```

Start the product web shell on an explicit port:

```bash
mix extravaganza.headless.web --port 4001 --json
```

Or let a Symphony-style workflow profile provide the port:

```yaml
---
server:
  port: 4001
  host: 127.0.0.1
---
```

```bash
mix extravaganza.headless.web --workflow WORKFLOW.md --json
```

Use port `0` for local ephemeral-port checks:

```bash
mix extravaganza.headless.web --port 0 --json
```

The web shell exposes the existing product routes rather than a separate lower
runtime server. The route plan maps Symphony's dashboard/API entrypoints to the
Extravaganza command and API surfaces:

- `GET /operator-console`
- `GET /api/v1/state`
- `GET /api/v1/status`
- `GET /api/v1/logs`
- `GET /api/v1/events`
- `GET /api/v1/:issue_identifier`
- `POST /api/v1/refresh`

## Deterministic headless proof (recommended first acceptance)

Run one command that exercises most surfaces in one sequence:

```bash
MIX_ENV=test mix extravaganza.headless.smoke --deterministic --same-run --json
```

For full fixture-backed proof against same-run references:

```bash
mix extravaganza.headless.smoke --json
```

Expected success pattern:

- `schema: "extravaganza.headless.response.v1"`
- `operation: "smoke"`
- `ok: true`
- stable `proof_class` and `readbacks`

## Non-fixture bootstrap proof

This repo ships a script that validates non-fixture bootstrap and command
runtime wiring:

```bash
mix run --no-start scripts/headless/assert_non_fixture_start.exs
```

It intentionally runs under `MIX_ENV=test` semantics through the script and
expects exit code `0` only when the start command returns a valid `ok` envelope.

## Live-gated product examples

Live examples are product entrypoints. They require `--live-product-path` to
start app runtime context. Without it, they intentionally run a fixture-backed
proof path and report `example_mode: "deterministic_fixture"` plus
`live_provider_effect?: false`.

```bash
mix extravaganza.headless.live.linear_source --live-product-path --json
mix extravaganza.headless.live.linear_current_states --live-product-path --json
mix extravaganza.headless.live.codex_turn --live-product-path --json
mix extravaganza.headless.live.linear_publication --live-product-path --json
mix extravaganza.headless.live.linear_graphql_tool --live-product-path --json
mix extravaganza.headless.live.github_evidence --live-product-path --json
mix extravaganza.headless.live.smoke --live-product-path --json
```

On this workstation, run live provider checks by prepending the local secrets
wrapper. The wrapper only injects shell credentials for this node; it is not
product behavior and the command output must not print secret values.

```bash
~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_source --live-product-path --json
~/scripts/with_bash_secrets mix extravaganza.headless.live.codex_turn --live-product-path --json
~/scripts/with_bash_secrets mix extravaganza.headless.live.github_evidence --live-product-path --json
~/scripts/with_bash_secrets mix extravaganza.headless.live.smoke --live-product-path --json
```

Wrapper script form (same command path):

```bash
mix run --no-start scripts/headless/live_linear_source.exs -- --live-product-path --json
mix run --no-start scripts/headless/live_smoke.exs -- --live-product-path --json
```

## API onboarding (programmatic operator view)

Start the web layer and call the full `/api/v1/*` headless route set.

```bash
cd /home/home/p/g/n/extravaganza
mix phx.server
```

Read live JSON envelopes at:

- `GET /api/v1/state`
- `GET /api/v1/status`
- `GET /api/v1/logs`
- `GET /api/v1/profile?workflow_path=WORKFLOW.md`
- `GET /api/v1/subjects/:subject_id`
- `GET /api/v1/subjects/:subject_id/source-publication`
- `GET /api/v1/runs/:run_id`
- `GET /api/v1/runs/:run_id/evidence`
- `GET /api/v1/events?run_id=run_id`
- `GET /api/v1/:issue_identifier`
- `GET /api/v1/reviews`

Mutation endpoints:

- `POST /api/v1/refresh`
- `POST /api/v1/profile/validate`
- `POST /api/v1/profile/reload`
- `POST /api/v1/source-publication`
- `POST /api/v1/subjects/:subject_id/source-publication`
- `POST /api/v1/subjects/:subject_id/actions/:action`
- `POST /api/v1/reviews/:decision_id/decisions/:decision`
- `POST /api/v1/subjects/:subject_id/read-lease`
- `POST /api/v1/subjects/:subject_id/stream-attach-lease`

All responses use the same top-level envelope shape as mix commands:

```json
{
  "ok": true,
  "schema": "extravaganza.headless.response.v1",
  "operation": "state",
  "data": {"schema_ref": "headless_state_snapshot.v1"},
  "refs": {}
}
```

## Symphony API Compatibility

Extravaganza preserves Symphony's minimum observability API routes while keeping
the product-owned envelope and AppKit-backed readback boundary:

- `GET /api/v1/state` returns `headless_state_snapshot.v1` and includes both
  `symphony_orchestrator_state` and `operator_dashboard` projections for the
  former terminal dashboard state.
- `GET /api/v1/:issue_identifier` returns `headless_subject_detail.v1` and
  includes `observability_issue` with issue identity, subject/source/run refs,
  runtime state, retry/attempt fields, recent events, tracked source metadata,
  and log links. Workspace identity is represented by a redacted workspace ref,
  not a raw path.
- `POST /api/v1/refresh` returns `202` with `headless_command_result.v1` and
  includes `observability_refresh` with queued/coalesced status, requested time,
  correlation id, and the poll/reconcile operations requested from the product
  headless surface.

Method-not-allowed, not-found, timeout, and unavailable responses use the same
standard JSON error envelope as the rest of the Extravaganza API.

## Script inventory

Use these scripts for onboarding and smoke runs:

- `scripts/headless/state.exs`
- `scripts/headless/start_fixture_run.exs`
- `scripts/headless/assert_non_fixture_start.exs`
- `scripts/headless/run_detail.exs`
- `scripts/headless/evidence_chain.exs`
- `scripts/headless/review_decision.exs`
- `scripts/headless/source_sync.exs`
- `scripts/headless/source_publish.exs`
- `scripts/headless/status.exs`
- `scripts/headless/logs.exs`
- `scripts/headless/profile_validate.exs`
- `scripts/headless/profile_reload.exs`
- `scripts/headless/live_linear_source.exs`
- `scripts/headless/live_codex_turn.exs`
- `scripts/headless/live_linear_publication.exs`
- `scripts/headless/live_github_evidence.exs`
- `scripts/headless/live_smoke.exs`

## Current behavior notes

- Live providers can be skipped for missing credentials; this is expected and
  represented in the response as `status: "skipped"`.
- Credential-supplied runs are still intentionally constrained by the same
  product path and lower bridge policy.
- No workspace paths or raw provider payloads are emitted in API/mix envelopes.
  They are redacted by contract.
- This guide is for the product-facing headless surface; lower runtime ownership
  is in AppKit/Mezzanine/Jido/Citadel.
