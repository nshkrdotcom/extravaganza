# Headless Provider Credentials and Verification

This guide lists every example path in `guides/headless_live_demo.md` and the
provider credentials required to exercise it.

## Credential-free commands

These examples do not require the provider credential variables listed in the live
matrix below:

- `mix extravaganza.headless.state --json`
- `mix extravaganza.headless.queue --json`
- `mix extravaganza.headless.subject --json`
- `mix extravaganza.headless.run --json`
- `mix extravaganza.headless.evidence --json`
- `mix extravaganza.headless.events --json`
- `mix extravaganza.headless.refresh --json`
- `mix extravaganza.headless.control --json`
- `mix extravaganza.headless.reviews --json`
- `mix extravaganza.headless.review --json`
- `mix extravaganza.headless.source_preview --json`
- `mix extravaganza.headless.source_sync --json`
- `mix extravaganza.headless.source_publish --json`
- `mix extravaganza.headless.status --json`
- `mix extravaganza.headless.logs --json`
- `mix extravaganza.headless.profile_validate --workflow WORKFLOW.md --json`
- `mix extravaganza.headless.profile_reload --workflow WORKFLOW.md --json`
- `mix extravaganza.headless.smoke --json`

`source_sync` runs through a deterministic fixture issue payload only when a
fixture context is supplied; if you run it without fixture context and without
live credentials, behavior follows the normal product command path.

## Live example credential map

The following credential references are embedded in the live example definitions:

| Live example | Command | Provider | Required env vars |
|---|---|---|---|
| linear source intake | `mix extravaganza.headless.live.linear_source --live-product-path --json` | Linear | `LINEAR_API_KEY` |
| linear current states | `mix extravaganza.headless.live.linear_current_states --live-product-path --json` | Linear | `LINEAR_API_KEY` |
| codex turn | `mix extravaganza.headless.live.codex_turn --live-product-path --json` | Codex | `OPENAI_API_KEY`, `CODEX_API_KEY` |
| linear publication | `mix extravaganza.headless.live.linear_publication --live-product-path --json` | Linear | `LINEAR_API_KEY` |
| linear GraphQL dynamic tool | `mix extravaganza.headless.live.linear_graphql_tool --live-product-path --json` | Linear | `LINEAR_API_KEY` |
| github evidence | `mix extravaganza.headless.live.github_evidence --live-product-path --json` | GitHub | `GH_TOKEN` or `GITHUB_TOKEN` |
| live smoke | `mix extravaganza.headless.live.smoke --live-product-path --json` | Linear + Codex + GitHub | All matching vars above |

Live command aliases in `scripts/headless/*.exs` are thin wrappers:
`live_linear_source.exs`, `live_linear_current_states.exs`,
`live_codex_turn.exs`, `live_linear_publication.exs`,
`live_linear_graphql_tool.exs`, `live_github_evidence.exs`, and
`live_smoke.exs`.

On this workstation, prepend `~/scripts/with_bash_secrets` when running live
provider checks so the local shell gets the provider variables without printing
their values:

```bash
~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_source --live-product-path --json
~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_current_states --live-product-path --json
~/scripts/with_bash_secrets mix extravaganza.headless.live.codex_turn --live-product-path --json
~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_publication --live-product-path --json
~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_graphql_tool --live-product-path --json
~/scripts/with_bash_secrets mix extravaganza.headless.live.github_evidence --live-product-path --json
~/scripts/with_bash_secrets mix extravaganza.headless.live.smoke --live-product-path --json
```

### Notes on how values are passed

- Prefer plain shell exports:
  - `export LINEAR_API_KEY=...`
  - `export OPENAI_API_KEY=...`
  - `export CODEX_API_KEY=...`
  - `export GH_TOKEN=...` or `export GITHUB_TOKEN=...`
- For linear examples, you can also pass the key through stdin with
  `--api-key-stdin`:
  `printf '%s' "$LINEAR_API_KEY" | mix ... --api-key-stdin`.
- For safety, keep secrets out of command logs and shell history.

## Verification workflow

Run each provider lane intentionally in two phases.

1. Deterministic fixture mode:

```bash
mix extravaganza.headless.live.linear_source --json
```

Expected `data` shape is:

```json
{
  "status": "skipped",
  "example_mode": "deterministic_fixture",
  "live_provider_effect?": false,
  "provider": "linear",
  "credential_refs": ["LINEAR_API_KEY"],
  "provider_effect": {
    "status": "skipped",
    "skip_reason": {
      "code": "credential_not_supplied_to_product_command"
    }
  }
}
```

Supplying credential flags without `--live-product-path` still stays in
deterministic fixture mode and reports
`credential_preflight.status: "requires_live_product_path"`.

2. Live product path mode:

```bash
~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_source --live-product-path --json
```

Expected change is a shifted code path:

```json
{
  "status": "completed",
  "example_mode": "live_product_path",
  "live_provider_effect?": true,
  "provider_effect": {
    "status": "receipt_recorded",
    "provider_request_sent?": true,
    "provider_response_received?": true,
    "receipt_recorded?": true,
    "product_readback_confirmed?": true
  }
}
```

Repeat that pattern for:

- `live.linear-current-states` with `LINEAR_API_KEY`
- `live.codex-turn` with `OPENAI_API_KEY` and `CODEX_API_KEY`
- `live.linear-publication` with `LINEAR_API_KEY`
- `live.linear-graphql-tool` with `LINEAR_API_KEY`
- `live.github-evidence` with `GH_TOKEN` or `GITHUB_TOKEN`
- `live.smoke` with all provider creds

## Provider Acceptance Matrix

All acceptance commands below must run as product-owned Extravaganza commands.
On this workstation, prepend `~/scripts/with_bash_secrets`; the wrapper only
injects local shell credentials and the JSON output must not print secret values.
Every live lane should report `example_mode: "live_product_path"`,
`live_provider_effect?: true`, `credential_preflight.status: "dispatchable"`,
and a `provider_effect` payload that includes `credential_present?`,
`credential_redeemed?`, `provider_request_sent?`,
`provider_response_received?`, `receipt_recorded?`,
`product_readback_confirmed?`, `authority_handoff_ref`,
`authority_packet_ref`, `connector_binding_ref`, `credential_lease_ref`,
`lower_request_ref`, and `lower_receipt_ref`.

| Lane | Exact command | Required refs and variables | Live side effect | Provider object and evidence fields |
|---|---|---|---|---|
| `live.linear-source` | `~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_source --live-product-path --json --source-states Todo,Backlog --project-slug ENG --team-id <linear-team-id> --assignee me` | `LINEAR_API_KEY`; optional `--source-states`, `--project-slug`, `--team-id`, `--assignee`; optional explicit `--connection-id`, `--credential-ref`, and `--credential-lease-ref` for pre-bound credentials. | Reads Linear issues through `linear.users.get_self`, `linear.issues.list`, and optionally `linear.issues.retrieve`; no provider write. | Identify read objects through `subjects[].provider_external_ref`, `subjects[].source_ref`, `source_binding_id`, `subject_count`, `source_state_names`, `viewer_lower_request_ref`, `viewer_lower_receipt_ref`, `lower_request_ref`, and `lower_receipt_ref`. |
| `live.linear-current-states` | `~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_current_states --live-product-path --json --issue-ids ENG-123,ENG-124` | `LINEAR_API_KEY`; `--issue-ids` or one `--issue-id`; same optional Linear source filters and explicit credential refs as source intake. | Reads current Linear issue states through `linear.users.get_self` and `linear.issues.list`; no provider write. | Identify read objects through `requested_issue_ids`, `missing_issue_ids`, `current_state_count`, `source_binding_id`, `viewer_lower_request_ref`, `viewer_lower_receipt_ref`, `lower_request_ref`, and `lower_receipt_ref`. |
| `live.codex-turn` | `~/scripts/with_bash_secrets mix extravaganza.headless.live.codex_turn --live-product-path --json` | `OPENAI_API_KEY` and `CODEX_API_KEY`; optional `--trace-id` and product host refs generated by the command. | Starts and completes a governed Codex app-server/session turn through `codex.session.turn`; provider prompt bodies remain redacted. | Identify the lower run and provider turn through `run_ref`, `workflow_ref`, `session_ref`, `turn_ref`, `runtime_control_session_ref`, `provider_session_id`, `provider_turn_id`, `session_start_lower_request_ref`, `session_start_lower_receipt_ref`, `session_stop_confirmed?`, `session_stop_lower_request_ref`, `session_stop_lower_receipt_ref`, `event_stream_confirmed?`, `token_accounting_confirmed?`, `token_totals_source`, `rate_limits_present?`, `lower_request_ref`, and `lower_receipt_ref`. |
| `live.linear-publication` | `~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_publication --live-product-path --json --issue-id ENG-123 --message "Extravaganza live publication proof"` | `LINEAR_API_KEY`; `--issue-id` or source-resolved first issue; optional `--comment-id`, `--message`, `--allow-create-fallback`, `--no-create-fallback`, `--state-id`, `--state-name`, and `--team-id`. | Writes or denies a governed Linear publication through `linear.comments.create`, `linear.comments.update`, or `linear.issues.update`; state updates may also read `linear.workflow_states.list`. | Identify the created/updated object through `source_publication_ref`, `comment_ref`, `workpad_refs`, `issue_id`, `state_id`, `state_name`, `state_lookup_lower_request_ref`, `state_lookup_lower_receipt_ref`, `lower_request_ref`, `lower_receipt_ref`, `lower_denial_ref`, `denial_class`, and `denial_reason`. |
| `live.linear-graphql-tool` | `~/scripts/with_bash_secrets mix extravaganza.headless.live.linear_graphql_tool --live-product-path --json --query "query Viewer { viewer { id } }" --variables-json "{}"` | `LINEAR_API_KEY`; `--query`; optional `--variables-json` JSON object. | Executes the governed Linear dynamic tool through `linear.graphql.execute`; no write unless the supplied query/mutation and lower policy allow it. | Identify the tool execution through `tool_name`, `dynamic_tool_response`, `lower_request_ref`, `lower_receipt_ref`, and the common authority/provider evidence fields. |
| `live.github-evidence` | `~/scripts/with_bash_secrets mix extravaganza.headless.live.github_evidence --live-product-path --json --repo nshkrdotcom/extravaganza --pull-number 17 --ref <head-sha>` | `GH_TOKEN` or `GITHUB_TOKEN`; `--repo`; optional `--pull-number`; optional `--ref` for status/check-run lookup. | Reads GitHub PR evidence through `github.pr.evidence`, including PR fetch, reviews, review comments, combined status, and check runs; no provider write. | Identify provider objects through `repo`, `pull_number`, `head_sha`, `evidence_ref`, `provider_ids`, `provider_refs`, `counts`, `receipt_refs`, `operation_receipts`, `lower_request_ref`, and `lower_receipt_ref`. |
| `live.smoke` | `~/scripts/with_bash_secrets mix extravaganza.headless.live.smoke --live-product-path --json` | All variables required by the six provider lanes above; optional lane-specific refs may be passed when the aggregate command needs deterministic provider targets. | Runs the aggregate product live proof for Linear source, Linear current states, Codex turn, Linear publication, Linear GraphQL, and GitHub evidence. | Identify completion through `required_operations`, `completed_operations`, `skipped_operations`, `failed_operations`, `provider_effect_count`, `all_provider_effects_completed?`, `correlation_ref`, `examples`, and each nested example's provider evidence fields. |

## Provider-by-provider confidence checks

To validate more than the command contract, run each provider acceptance lane in
the owning connector package after this repo-level onboarding:

- Linear: follow `/home/home/p/g/n/jido_integration/connectors/linear/docs/live_acceptance.md`
  and run `scripts/live_acceptance.sh all` in
  `/home/home/p/g/n/jido_integration/connectors/linear`.
- GitHub: follow `/home/home/p/g/n/jido_integration/connectors/github/docs/live_acceptance.md`
  and run `scripts/live_acceptance.sh all` in
  `/home/home/p/g/n/jido_integration/connectors/github`.
- Codex: verify with the owning provider package docs (`/home/home/p/g/n/codex_sdk/README.md`
  and `/home/home/p/g/n/jido_integration/connectors/codex_cli/README.md`) before
  attempting write-oriented extravaganza workflows.

## Quick matrix for scripts and API

Use this table to keep local docs in sync:

| Artifact | Example or endpoint | Requires provider creds |
|---|---|---|
| `scripts/headless/live_linear_source.exs` | live linear source | yes |
| `scripts/headless/live_codex_turn.exs` | live codex turn | yes |
| `scripts/headless/live_linear_publication.exs` | live linear publication | yes |
| `scripts/headless/live_github_evidence.exs` | live github evidence | yes |
| `scripts/headless/live_smoke.exs` | live smoke bundle | yes |
| `/api/v1` routes | read + control surfaces | no (uses existing product envelope data) |

For API proof, run `mix phx.server` and verify JSON envelopes in
`guides/headless_live_demo.md` while you use the same command sequence above to
prime fixture or live-product state.
