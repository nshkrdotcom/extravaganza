# Headless API Reference

This reference lists the public headless product surface: Mix commands, HTTP
routes, required arguments, live prerequisites, response envelope fields, and
standard error classes.

Provider mode means:

- `deterministic-only`: the command or route uses fixture/product-local state and
  does not contact a live provider.
- `read-live`: the live product path may read from Linear, GitHub, or Codex
  provider infrastructure after explicit guardrail acknowledgement.
- `write-live`: the live product path may create, update, close, or otherwise
  mutate provider-side state after explicit guardrail acknowledgement.

Live provider checks on this workstation use:

```bash
~/scripts/with_bash_secrets mix <task> --live-product-path --ack-headless-guardrails --json
```

The wrapper only injects local shell environment for the process. Product code
does not read or print raw provider secrets.

## Command Reference

Common options accepted by most commands:

- `--json`: emit the standard JSON envelope.
- `--pretty`: pretty-print JSON where the command uses `HeadlessJSON`.
- `--tenant-id TENANT_ID` and `--pack-version VERSION`: select product test or
  local product scope.
- `--trace-id TRACE_ID`: caller-supplied W3C trace ID for commands that carry a
  request context.
- `--workflow PATH`, `--workflow-path PATH`, `--cwd DIR`, `--profile-cache PATH`,
  and repeated `--env KEY=VALUE`: explicit Symphony workflow profile import
  inputs. Runtime product code does not read ambient OS env.
- `--ack-headless-guardrails`: required for mutating product commands and live
  product path commands. The legacy acknowledgement flag is still accepted.

| Command | Required arguments | Provider mode | Live prerequisites | Output data |
| --- | --- | --- | --- | --- |
| `mix extravaganza.headless.state --json` | None. | deterministic-only | None. | `operator_dashboard` state, route coverage, source/run/review/evidence summaries. |
| `mix extravaganza.headless.queue --json` | None. | deterministic-only | None. | Operator queue page with subject refs, run refs, review posture, and pagination. |
| `mix extravaganza.headless.subject SUBJECT_ID --json` | Optional `SUBJECT_ID`; fixture default is used when omitted. | deterministic-only | None. | Subject detail, actions, timeline, unified trace, read/stream lease posture, lineage summary. |
| `mix extravaganza.headless.run RUN_ID --json` | Optional `RUN_ID`; fixture default is used when omitted. | deterministic-only | None. | Run detail, status, runtime row, lower receipt refs, governance refs. |
| `mix extravaganza.headless.start --ack-headless-guardrails --json` | Optional `--title`, `--description`, `--issue-id`, `--idempotency-key`. | deterministic-only | None. | Product-owned start-run result with `run_ref`, `subject_ref`, and idempotency proof. |
| `mix extravaganza.headless.refresh --ack-headless-guardrails --json` | Optional `--idempotency-key`. | deterministic-only | None. | Refresh command result and idempotency key. |
| `mix extravaganza.headless.control SUBJECT_ID ACTION --ack-headless-guardrails --json` | Optional positional `SUBJECT_ID` and `ACTION`; equivalent flags are `--subject-id` and `--action`. | deterministic-only | None. | Operator control command result for retry, pause, resume, cancel, or supported local action. |
| `mix extravaganza.headless.reviews --json` | None. | deterministic-only | None. | Pending review page and decision refs. |
| `mix extravaganza.headless.review DECISION_ID --decision accept --ack-headless-guardrails --json` | Optional `DECISION_ID`; `--decision accept`, `reject`, or `waive`; optional `--reason` and `--subject-id`. | deterministic-only | None. | Review decision command result and decision refs. |
| `mix extravaganza.headless.source_preview SUBJECT_ID --json` | Optional `SUBJECT_ID`. | deterministic-only | None. | Linear source-publication preview without provider write. |
| `mix extravaganza.headless.source.sync --json` | Optional deterministic Linear-shaped issue flags. | deterministic-only | None. | Source sync/upsert result and subject refs. |
| `mix extravaganza.headless.source_sync --json` | Alias for `mix extravaganza.headless.source.sync --json`. | deterministic-only | None. | Same as source sync. |
| `mix extravaganza.headless.source_publish SUBJECT_ID --ack-headless-guardrails --json` | Optional `SUBJECT_ID`; optional `--effect`, `--message`, `--idempotency-key`. | deterministic-only | None. | Governed product source-publication result. |
| `mix extravaganza.headless.profile --json` | Optional workflow import flags. | deterministic-only | None. | Imported Symphony workflow profile, validation result, app-kit profile mapping. |
| `mix extravaganza.headless.profile_validate --json` | Optional workflow import flags. | deterministic-only | None. | Validation-only profile result or standard profile error. |
| `mix extravaganza.headless.profile_reload --ack-headless-guardrails --json` | Optional workflow import flags and profile cache path. | deterministic-only | None. | Reload result and product profile apply proof. |
| `mix extravaganza.headless.status --json` | Optional `--logs-root` and workflow import flags. | deterministic-only | None. | Runtime status, cleanup posture, persisted runtime metadata. |
| `mix extravaganza.headless.logs --json` | Optional `--logs-root`, `--run-id`, `--cursor`, `--limit`. | deterministic-only | None. | Runtime log page using `headless_runtime_logs.v1`; secret-like values are redacted. |
| `mix extravaganza.headless.preflight --json --temporal-status reachable` | Optional `--temporal-status reachable|unavailable|not_checked`, `--source-binding-ref REF`, `--source-binding-refs REF,REF`, `--credential-refs REF,REF`, and `--skip-app-start` for fixture-only checks. | deterministic-only | For full live stack readiness, run the Mezzanine substrate commands from `/home/home/p/g/n/mezzanine`: `just dev-up`, `just dev-status`, `just dev-logs`, and `just temporal-ui` as needed. | Product dependency preflight using `headless_dependency_preflight.v1`: app start, DB repo posture, Temporal substrate status, AppKit backend resolution, source binding refs, and credential refs. |
| `mix extravaganza.headless.stop --confirm-no-active-lower-runs --ack-headless-guardrails --json` | Requires `--confirm-no-active-lower-runs` unless active lower-run refs are supplied for blocking proof. Optional `--active-lower-run-ref REF`, `--active-lower-run-refs REF,REF`, and `--reason`. | deterministic-only | None. | Graceful shutdown/offline status using `headless_shutdown.v1`; renders `app_status=offline` only after no-active-lower-run posture is proved and blocks when active lower runs are present. |
| `mix extravaganza.headless.evidence RUN_ID --json` | Optional `RUN_ID`. | deterministic-only | None. | Evidence chain, authority refs, lower request/receipt refs, provider evidence refs. |
| `mix extravaganza.headless.events RUN_ID --json` | Optional `RUN_ID`; optional `--cursor`, `--limit`. | deterministic-only | None. | Event page, event refs, event kinds, and run/subject refs. |
| `mix extravaganza.headless.smoke --deterministic --same-run --json` | None. | deterministic-only | None. | Same-run proof over state, run, evidence, events, leases, routes, and readbacks. |
| `mix extravaganza.headless.web --port 4000 --json` | `--port` unless supplied by workflow profile. Optional `--host`, `--once`, workflow flags. | deterministic-only | None for deterministic routes; live routes have their own ack and credentials. | Web server plan or running Phoenix headless API shell. |
| `mix extravaganza.headless.specs.check` | None. | deterministic-only | None. | QC task; exits non-zero if public headless functions miss `@spec`s. |

### Live Commands

Every live command defaults to deterministic fixture mode unless
`--live-product-path` is present. Live product path mode requires
`--ack-headless-guardrails`. On this workstation, prepend
`~/scripts/with_bash_secrets`.

| Command | Required arguments | Provider mode | Live prerequisites | Output data |
| --- | --- | --- | --- | --- |
| `mix extravaganza.headless.live.linear_source --live-product-path --ack-headless-guardrails --json --api-key-stdin` | Pipe `LINEAR_API_KEY` through stdin unless explicit lower credential refs are supplied; optional `--source-states`, `--project-slug`, `--team-id`, `--assignee`. | read-live | `LINEAR_API_KEY` via `--api-key-stdin`, or `--connection-id`, `--credential-ref`, `--credential-lease-ref`. | Linear subjects, `source_binding_id`, provider external refs, viewer/lower request and receipt refs. |
| `mix extravaganza.headless.live.linear_current_states --live-product-path --ack-headless-guardrails --json --api-key-stdin` | Pipe `LINEAR_API_KEY` through stdin unless explicit lower credential refs are supplied; one `--issue-id` or comma-separated `--issue-ids`; optional source filters. | read-live | `LINEAR_API_KEY` via stdin or explicit lower credential refs. | Requested/missing issue IDs, current state count, source binding, lower receipt refs. |
| `mix extravaganza.headless.live.codex_turn --live-product-path --ack-headless-guardrails --json` | Optional `--trace-id`. | write-live | `OPENAI_API_KEY`; include `CODEX_API_KEY` only when the configured Codex connector profile requires it. | Codex session/turn refs, runtime control session ref, provider session/turn IDs, event stream and token accounting confirmations, lower receipt refs. |
| `mix extravaganza.headless.live.linear_publication --live-product-path --ack-headless-guardrails --json --api-key-stdin` | Pipe `LINEAR_API_KEY` through stdin unless explicit lower credential refs are supplied; `--issue-id` unless source resolution can select the first issue; optional `--message`, `--comment-id`, `--state-id`, `--state-name`, `--team-id`, `--allow-create-fallback`, `--no-create-fallback`. | write-live | `LINEAR_API_KEY` via stdin or explicit lower credential refs. | Source-publication ref, comment/workpad refs, state lookup refs, lower denial or lower receipt refs. |
| `mix extravaganza.headless.live.linear_graphql_tool --live-product-path --ack-headless-guardrails --json --api-key-stdin` | Pipe `LINEAR_API_KEY` through stdin unless explicit lower credential refs are supplied; `--query`; optional `--variables-json` object. | read-live or write-live | `LINEAR_API_KEY` via stdin or explicit lower credential refs; effect depends on the governed GraphQL query or mutation. | Dynamic tool response, tool name, authority handoff, lower request/receipt refs. |
| `mix extravaganza.headless.live.github_evidence --live-product-path --ack-headless-guardrails --json` | `--repo OWNER/REPO`; optional `--pull-number`, `--ref`. | read-live | `GH_TOKEN` or `GITHUB_TOKEN`. | PR evidence ref, provider IDs/refs, review/comment/status/check counts, operation receipts. |
| `mix extravaganza.headless.live.github_pr_cleanup --live-product-path --ack-headless-guardrails --json --confirm-close` | `--repo OWNER/REPO`, `--branch BRANCH`, and explicit `--confirm-close`; optional `--pull-number`, `--closing-comment`. | write-live | `GH_TOKEN` or `GITHUB_TOKEN`. | Matching pull numbers, closed pull numbers, write operations, provider refs, operation receipts. This command is intentionally excluded from live smoke. |
| `mix extravaganza.headless.live.smoke --live-product-path --ack-headless-guardrails --json --api-key-stdin --assignee all --issue-id LINEAR_ISSUE_UUID --issue-ids LINEAR_ISSUE_UUID --repo OWNER/REPO --pull-number PR_NUMBER --ref HEAD_SHA` | Requires Linear stdin or lower connection binding plus lane-specific provider targets. | read-live and write-live | Credentials required by Linear source/current-states/publication/GraphQL, Codex turn, and GitHub evidence. GitHub PR cleanup is not included. | Required/completed/skipped/failed operations, provider effect count, all-provider-effects flag, nested example readbacks. |

## HTTP API Reference

All HTTP routes return JSON and use the same success/error envelope as Mix tasks.
Live routes require `ack_headless_guardrails=true` or `guardrails_ack=true` in
the request body/query params. Raw credential parameters such as
`linear_api_key`, `github_token`, `gh_token`, `openai_api_key`, and
`codex_api_key` are rejected with detail reason
`raw_provider_credential_param_not_supported`.

| Route | Required arguments | Provider mode | Notes |
| --- | --- | --- | --- |
| `GET /api/v1/state` | None. | deterministic-only | State snapshot and operator dashboard projection. |
| `GET /api/v1/status` | None. | deterministic-only | Runtime status readback. |
| `GET /api/v1/preflight` | Optional `temporal_status`, `source_binding_refs`, `credential_refs`, and `skip_app_start` query params. | deterministic-only | Product dependency preflight. Runtime mechanics stay behind AppKit and the Mezzanine `just` substrate. |
| `GET /api/v1/logs` | Optional `logs_root`, `run_id`, `cursor`, `limit`. | deterministic-only | Runtime logs page. |
| `POST /api/v1/shutdown` | JSON body with `confirm_no_active_lower_runs: true`, or active lower-run refs for blocking proof. | deterministic-only | Product graceful shutdown/offline status; standard error if lower-run posture is missing or active lower runs are present. |
| `GET /api/v1/profile` | Optional workflow query params. | deterministic-only | Imported workflow profile. |
| `POST /api/v1/profile/validate` | Optional workflow params in JSON body. | deterministic-only | Profile validation result. |
| `POST /api/v1/profile/reload` | Optional workflow/profile-cache params. | deterministic-only | Profile reload/apply path. |
| `POST /api/v1/source-publication` | `subject_ref` or subject fields accepted by product source-publication path. | deterministic-only | Product-owned source-publication command. |
| `POST /api/v1/live/linear-source` | Guardrail ack; optional Linear source filters. | read-live | Product-host live Linear source example. |
| `POST /api/v1/live/linear-current-states` | Guardrail ack and `issue_id` or `issue_ids` for live product path. | read-live | Product-host live Linear current-state example. |
| `POST /api/v1/live/codex-turn` | Guardrail ack. | write-live | Product-host live Codex turn example. |
| `POST /api/v1/live/linear-publication` | Guardrail ack and live publication issue/message inputs. | write-live | Product-host live Linear publication example. |
| `POST /api/v1/live/linear-graphql-tool` | Guardrail ack and `query`; optional `variables_json`. | read-live or write-live | Product-host governed Linear GraphQL dynamic tool. |
| `POST /api/v1/live/github-evidence` | Guardrail ack and `repo`; optional `pull_number`, `ref`. | read-live | Product-host live GitHub evidence example. |
| `POST /api/v1/live/github-pr-cleanup` | Guardrail ack, `repo`, `branch`, and `confirm_close=true`. | write-live | Product-host live GitHub PR cleanup; destructive lane. |
| `POST /api/v1/live/smoke` | Guardrail ack and any lane-specific provider targets. | read-live and write-live | Aggregate live smoke without GitHub PR cleanup. |
| `GET /api/v1/subjects/:subject_id` | `subject_id`. | deterministic-only | Subject detail. |
| `GET /api/v1/subjects/:subject_id/source-publication` | `subject_id`. | deterministic-only | Source-publication preview. |
| `POST /api/v1/subjects/:subject_id/source-publication` | `subject_id`; optional `message`, `effect`, `idempotency_key`. | deterministic-only | Product-owned publication command. |
| `GET /api/v1/runs/:run_id` | `run_id`. | deterministic-only | Run detail. |
| `GET /api/v1/runs/:run_id/evidence` | `run_id`. | deterministic-only | Evidence chain for a run. |
| `GET /api/v1/events` | Optional `run_id`, `cursor`, `limit`. | deterministic-only | Event page. |
| `POST /api/v1/refresh` | Optional `idempotency_key`. | deterministic-only | Refresh command. |
| `POST /api/v1/subjects/:subject_id/actions/:action` | `subject_id`, `action`. | deterministic-only | Operator action command. |
| `POST /api/v1/subjects/:subject_id/control/:action` | `subject_id`, `action`. | deterministic-only | Compatibility alias for operator action command. |
| `POST /api/v1/subjects/:subject_id/read-lease` | `subject_id`. | deterministic-only | Issues a governed read lease for lower trace readback. |
| `POST /api/v1/subjects/:subject_id/stream-attach-lease` | `subject_id`. | deterministic-only | Issues a governed stream attach lease. |
| `GET /api/v1/reviews` | Optional pagination params. | deterministic-only | Pending review page. |
| `POST /api/v1/reviews/:decision_id/decisions/:decision` | `decision_id`, `decision`; optional `reason`. | deterministic-only | Records accept/reject/waive review decision. |
| `GET /api/v1/:issue_identifier` | `issue_identifier`. | deterministic-only | Symphony-compatible issue lookup route; specific routes above take precedence. |

Wrong verbs return `method_not_allowed`. Unknown routes return `not_found`.

## Success Envelope

Successful task and route responses use schema
`extravaganza.headless.response.v1`.

| Field | Meaning |
| --- | --- |
| `ok` | Always `true` on success. |
| `schema` | Envelope schema. |
| `operation` | Operation name, for example `state`, `live.github-evidence`, or `web`. |
| `trace_id` | W3C trace ID when supplied or derived from data refs. |
| `idempotency_key` | Caller idempotency key or key discovered in readback refs. |
| `runtime_profile_ref` | Runtime profile ref when present in options or data. |
| `data` | Operation-specific payload. |
| `refs` | Extracted refs such as `subject_ref`, `run_ref`, `workflow_ref`, `authority_ref`, `decision_ref`, `connector_manifest_ref`, `capability_negotiation_ref`, `lower_request_ref`, `lower_receipt_ref`, `lower_denial_ref`, `source_publication_ref`, `evidence_chain_ref`, `event_page_ref`, and `idempotency_key`. |
| `warnings` | Non-fatal warnings. |
| `generated_at` | ISO-8601 timestamp. |

## Error Envelope

Error responses use schema `extravaganza.headless.error.v1`.

| Field | Meaning |
| --- | --- |
| `ok` | Always `false` on error. |
| `schema` | Error envelope schema. |
| `operation` | Operation name. |
| `trace_id` | Trace ID when supplied. |
| `error.code` | Machine-readable error code. |
| `error.message` | Human-readable message. |
| `error.class` | Stable class used by clients for handling. |
| `error.retryable?` | Whether retrying may succeed. |
| `error.missing_refs` | Missing capability, credential, profile, or runtime refs. |
| `error.details` | Sanitized operation-specific details. Secret-like fields and absolute paths are redacted. |
| `generated_at` | ISO-8601 timestamp. |

## Error Classes

| Class | Representative codes | Meaning |
| --- | --- | --- |
| `missing_live_prerequisite` | `live_product_path_required`, `requires_live_product_path`, `missing_live_linear_publication_issue` | Live command/route is missing explicit live path or required live target refs. |
| `missing_credential` | `credential_stdin_empty`, `credential_not_supplied_to_product_command`, `missing_linear_api_token`, `missing_provider_credential` | Provider credential was absent or empty. |
| `invalid_profile` | `invalid_workflow_config`, `workflow_front_matter_not_a_map`, `workflow_parse_error`, `missing_workflow_file`, `unsupported_tracker_kind`, `incompatible_product_runtime_profile`, `unsupported_runtime_profile_change` | Imported Symphony workflow/profile data cannot be applied by this product. |
| `invalid_request` | `linear_graphql_variables_json_must_decode_to_object`, `invalid_linear_graphql_variables_json`, `bad_request`, `invalid_action` | Request shape or command arguments are invalid. |
| `provider_denial` | `provider_denied`, `provider_authority_denied`, `policy_denied`, `action_denied`, `unauthorized_lower_read` | Governed provider/lower read or action was denied. |
| `provider_error` | `provider_failed`, `provider_error`, `provider_timeout` | Provider dispatch happened or was attempted but failed or timed out. |
| `app_not_started` | `live_surface_dependency_failed`, `startup_failed`, `app_not_started`, `temporal_substrate_unavailable` | Required app/substrate dependency was not started or reachable. |
| `product_host_unavailable` | `runtime_installation_not_provisioned` | Product host/runtime installation is not provisioned. |
| `operator_ack_required` | `operator_ack_required` | A mutating or live operation needs explicit acknowledgement. |
| `headless_error` | `unavailable`, `snapshot_timeout`, `archived`, `not_found`, `method_not_allowed`, `internal_error` | Generic or route-level headless errors. |

HTTP live routes also reject raw provider credential params with detail reason
`raw_provider_credential_param_not_supported`; pass credential refs or use the
local shell wrapper for workstation live checks instead.
