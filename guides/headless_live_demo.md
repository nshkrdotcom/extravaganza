# Headless Live Demo Onboarding

Use this guide to run the full headless demo path end-to-end through the
Extravaganza product command surface, inspect JSON readbacks, and exercise live
provider examples.

## What you get out of the box

These are the user-facing headless entrypoints you can call today:

- Mix tasks (stable operator commands)
- REST API routes under `/api/v1/*` (shared presenter-backed envelopes)
- Example scripts under `scripts/headless/` for replayable command flows

The same command/result surface is used for fixture and live paths.

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
```

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
proof path.

```bash
mix extravaganza.headless.live.linear_source --live-product-path --json
mix extravaganza.headless.live.codex_turn --live-product-path --json
mix extravaganza.headless.live.linear_publication --live-product-path --json
mix extravaganza.headless.live.github_evidence --live-product-path --json
mix extravaganza.headless.live.smoke --live-product-path --json
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
- `GET /api/v1/subjects/:subject_id`
- `GET /api/v1/subjects/:subject_id/source-publication`
- `GET /api/v1/runs/:run_id`
- `GET /api/v1/runs/:run_id/evidence`
- `GET /api/v1/events?run_id=run_id`
- `GET /api/v1/:issue_identifier`
- `GET /api/v1/reviews`

Mutation endpoints:

- `POST /api/v1/refresh`
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

## Script inventory

Use these scripts for onboarding and smoke runs:

- `scripts/headless/state.exs`
- `scripts/headless/start_fixture_run.exs`
- `scripts/headless/assert_non_fixture_start.exs`
- `scripts/headless/run_detail.exs`
- `scripts/headless/evidence_chain.exs`
- `scripts/headless/review_decision.exs`
- `scripts/headless/source_sync.exs`
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
