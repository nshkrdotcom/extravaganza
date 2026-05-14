# Symphony Headless Gap Analysis

Purpose: document where Extravaganza currently implements the headless part of
the Symphony specification through either mix tasks, the programmatic API, or
examples, and where that implementation is still partial.

References:

- `/home/home/p/g/n/symphony/SPEC.md`
- `apps/extravaganza_core/lib/mix/tasks/extravaganza.headless.ex`
- `apps/extravaganza_core/lib/extravaganza/headless_cli.ex`
- `apps/extravaganza_core/lib/extravaganza/headless_surface.ex`
- `apps/extravaganza_core/lib/extravaganza/product_host.ex`
- `apps/extravaganza_web/lib/extravaganza_web/router.ex`
- `apps/extravaganza_web/lib/extravaganza_web/controllers/api/headless_controller.ex`
- `scripts/headless/*.exs`

## Scope and review method

- **Symphony baseline**: this analysis focuses on the headless API contract in
  `SPEC.md`, especially the optional HTTP extension (Section 13.7), command/mix
  entrypoints, and orchestration-facing behavior that is surfaced as external readback
  and operator actions.
- **Coverage axes**:
  - Mix command/API entrypoints in `Extravaganza.HeadlessCLI`
  - Programmatic API via `Extravaganza.HeadlessSurface`, `Extravaganza.ProductHost`, and
    `/api/v1` routes
  - Example scripts in `scripts/headless/` and output fixtures under `examples/headless/`

- **Status legend**:
  - **Done**: implemented end-to-end on this repo and reachable from at least one
    required operator path.
  - **Partial**: command/API exists, but behavior differs from `SPEC` or is narrower
    than specified.
  - **Gap**: no implementation in this repo today.

## Headless surface matrix vs SPEC

| Symphony behavior | Mix command | Programmatic API (`/api` + modules) | Example | Status |
| --- | --- | --- | --- | --- |
| Start/enable optional HTTP server extension (`--port`, `server.port`) | **N/A in headless product CLI** | Phoenix app offers routes when started, but no CLI `--port`/`server.port` activation path in command layer | No dedicated example | Gap |
| Human-readable dashboard at `/` (optional) | N/A | `ExtravaganzaWeb` renders app pages for operator web surface, not a symphony dashboard contract | N/A | Gap |
| `GET /api/v1/state` | `mix extravaganza.headless.state --json` | `GET /api/v1/state` (maps to `HeadlessSurface.state_snapshot/2`) | `scripts/headless/state.exs` and fixture `examples/headless/state.json` | Done |
| `GET /api/v1/<issue_identifier>` equivalent | `mix extravaganza.headless.subject --json` can target by subject id; issue-identifier style is API-only via `:issue_subject` route | `GET /api/v1/:issue_identifier`; also `GET /api/v1/subjects/:subject_id` | No dedicated issue-identifier script; API tested in controller spec | Partial |
| `POST /api/v1/refresh` best-effort trigger | `mix extravaganza.headless.refresh --ack-headless-guardrails --json` | `POST /api/v1/refresh` (`HeadlessSurface.request_refresh/2`) | no script; no fixture example file | Done |
| Unsupported methods return JSON 405 | N/A | `match/2` routes return 405 | API tests cover this path | Done |
| Error envelopes for known failure modes | Envelope contract via `HeadlessJSON.error/2` | `HeadlessController` maps known errors to contract status codes | API tests cover all listed mapping points | Done |
| State includes running/retry/token summary | `mix extravaganza.headless.state --json` | `state` presenter exposes rows, turns and future slots plus status fields from `AppKit` readback | `state` fixture output exists | Partial |
| Subject-level runtime detail by issue id | `mix extravaganza.headless.subject --json` / positional subject id | `GET /api/v1/subjects/:subject_id` and `GET /api/v1/:issue_identifier` | no dedicated script per issue identifier; `subject` API coverage via tests | Partial |
| Refresh/retry/controls as accepted command envelopes | `mix extravaganza.headless.refresh --ack-headless-guardrails --json`, `mix extravaganza.headless.control --ack-headless-guardrails --action ... --json` | `POST /api/v1/refresh`, `/subjects/:subject_id/actions/:action`, `/subjects/:subject_id/control/:action` | no direct script for control; review_decision/restart example exists | Done |
| Review listing and decisioning | `mix extravaganza.headless.reviews --json`, `mix extravaganza.headless.review --ack-headless-guardrails --decision ... --json` | `GET /api/v1/reviews`, `POST /api/v1/reviews/:decision_id/decisions/:decision` | `scripts/headless/review_decision.exs`, fixture `review` output not stored | Done |
| Queue/runtime-row readback | `mix extravaganza.headless.queue --json` | no dedicated `/api/v1/queue` route; queue included via state/readback projections | no queue script | Partial |
| Run detail readback | `mix extravaganza.headless.run --json` | `GET /api/v1/runs/:run_id` | `scripts/headless/run_detail.exs`, `examples/headless/run.json` | Done |
| Evidence chain readback | `mix extravaganza.headless.evidence --json` | `GET /api/v1/runs/:run_id/evidence` | `scripts/headless/evidence_chain.exs`, `examples/headless/evidence.json` | Done |
| Events readback by run | `mix extravaganza.headless.events --json` | `GET /api/v1/events?run_id=...` | `examples/headless/events.json` (event page envelope) | Done |
| Source publication preview | `mix extravaganza.headless.source_preview --json` | `GET /api/v1/subjects/:subject_id/source-publication` | source publication route coverage via tests | Done |
| Governed source publication | `mix extravaganza.headless.source_publish --ack-headless-guardrails --json` | `POST /api/v1/source-publication`, `POST /api/v1/subjects/:subject_id/source-publication` | `scripts/headless/source_publish.exs` | Done |
| Source sync/inbound shaping | `mix extravaganza.headless.source.sync --ack-headless-guardrails --json` | `ProductHost.sync_linear_source/2`, `HeadlessSurface.sync_linear_source/2` | `scripts/headless/source_sync.exs` | Done |
| Runtime status/logs | `mix extravaganza.headless.status --json`, `mix extravaganza.headless.logs --json` | `GET /api/v1/status`, `GET /api/v1/logs` | `scripts/headless/status.exs`, `scripts/headless/logs.exs` | Done |
| Symphony workflow profile validate/reload | `mix extravaganza.headless.profile_validate --workflow WORKFLOW.md --json`, `mix extravaganza.headless.profile_reload --workflow WORKFLOW.md --ack-headless-guardrails --json` | `POST /api/v1/profile/validate`, `POST /api/v1/profile/reload`, `GET /api/v1/profile` | `scripts/headless/profile_validate.exs`, `scripts/headless/profile_reload.exs` | Done |
| Subject read lease + stream attach lease (operational helper methods) | N/A as direct mix command | `GET` equivalent in API: `/api/v1/subjects/:subject_id/read-lease`, `/api/v1/subjects/:subject_id/stream-attach-lease` | no script today, but API and module paths exist | Partial |
| Start run command | `mix extravaganza.headless.start --ack-headless-guardrails --json` for non-fixture start; fixture start remains `mix extravaganza.headless.start --fixture headless_m1 --json` | `ProductHost.start_run/2` + `ExtravaganzaWeb` browser route surface uses same presenters | `scripts/headless/assert_non_fixture_start.exs`, `scripts/headless/start_fixture_run.exs` | Done |
| Same-run deterministic proof chain | `mix extravaganza.headless.smoke --deterministic --same-run --json` | `ProductHost.same_run_smoke/1` and same underlying readbacks | no dedicated example script; endpoint coverage via tests | Partial |
| Live example command matrix (linear source, codex turn, linear publication, github evidence) | `mix extravaganza.headless.live.linear_source|codex_turn|linear_publication|github_evidence --json` and `mix extravaganza.headless.live.smoke --json` | no direct API for live example command path; this is command only by design | `scripts/headless/live_*.exs` wrappers | Done |

## Symphony behavior that is intentionally out of command/API scope

These are orchestration behaviors present in `SPEC` but not currently the exposed
product entrypoint contract in this repo:

- CLI workflow-path semantics (`WORKFLOW.md` positional path and direct port mode)
- Long-running daemon tick/retry/discovery lifecycle and live config hot reload
- Explicit terminal-state cleanup policy assertions as first-class CLI options
- Workspace hook execution and full scheduler queue mutation control from CLI

Those are still being represented in the lower stack (`Mezzanine`/`AppKit`/`Citadel`)
but are not currently user-operable through `Extravaganza` mix command API.

## What exists in examples and what does not

### Covered by examples

- Base readback commands (`state`, `run`, `events`, `evidence`)
- Run/start path checks (`start_fixture_run`, `assert_non_fixture_start`)
- Review recording (`review_decision`)
- Source intake command (`source_sync`)
- Live matrix command wrappers (`live_*`, `live_smoke`) with deterministic skip
  behavior when provider credentials are absent

### Missing as direct example artifacts

- Queue and refresh/control invocation wrappers (`queue`, `refresh`, `control`)
- Read-lease/stream-attach-lease examples
- Source publication preview
- A dedicated same-run smoke replay example script

## Evidence anchors (for audit)

- Mix command inventory: `apps/extravaganza_core/lib/mix/tasks/extravaganza.headless.ex`
- CLI parser and operation dispatch: `apps/extravaganza_core/lib/extravaganza/headless_cli.ex`
- API routes and method constraints: `apps/extravaganza_web/lib/extravaganza_web/router.ex`
- API error/status mapping: `apps/extravaganza_web/lib/extravaganza_web/controllers/api/headless_controller.ex`
- Headless programmatic surface: `apps/extravaganza_core/lib/extravaganza/headless_surface.ex`,
  `apps/extravaganza_core/lib/extravaganza/product_host.ex`
- Example script inventory and expected paths: `scripts/headless/*.exs`, `examples/headless/*.json`

## Practical remediation notes

1. Add mix task coverage if the team wants command parity for lease operations
   (`read-lease`, `stream-attach-lease`) and `source_preview`.
2. Add explicit issue-identifier examples for API read paths if onboarding requires
   command-first parity.
3. Continue validating live examples when provider-level bridges are enabled by default;
   current command responses are valid and explicitly tagged when provider effects are
   skipped.
