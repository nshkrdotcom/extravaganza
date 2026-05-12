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
| codex turn | `mix extravaganza.headless.live.codex_turn --live-product-path --json` | Codex | `OPENAI_API_KEY`, `CODEX_API_KEY` |
| linear publication | `mix extravaganza.headless.live.linear_publication --live-product-path --json` | Linear | `LINEAR_API_KEY` |
| github evidence | `mix extravaganza.headless.live.github_evidence --live-product-path --json` | GitHub | `GH_TOKEN` or `GITHUB_TOKEN` |
| live smoke | `mix extravaganza.headless.live.smoke --live-product-path --json` | Linear + Codex + GitHub | All matching vars above |

Live command aliases in `scripts/headless/*.exs` are thin wrappers:
`live_linear_source.exs`, `live_codex_turn.exs`, `live_linear_publication.exs`,
`live_github_evidence.exs`, and `live_smoke.exs`.

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

1) Credential-missing dry run:

```bash
mix extravaganza.headless.live.linear_source --live-product-path --json
```

Expected `data` shape is:

```json
{
  "status": "skipped",
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

2) Credential-provided lane run:

```bash
export LINEAR_API_KEY=...
mix extravaganza.headless.live.linear_source --live-product-path --json
```

Expected change is a shifted code path:

```json
{
  "provider_effect": {
    "status": "live_provider_effect_deferred"
  }
}
```

The command still reports `"status": "skipped"` overall because this repo keeps live
provider side effects explicitly owned by the governed bridge layer, so the
provider call is only confirmed through lower-layer acceptance proof surfaces.

Repeat that pattern for:

- `live.codex-turn` with `OPENAI_API_KEY` and `CODEX_API_KEY`
- `live.linear-publication` with `LINEAR_API_KEY`
- `live.github-evidence` with `GH_TOKEN` or `GITHUB_TOKEN`
- `live.smoke` with all provider creds

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
