# Monorepo Project Map

- `./apps/extravaganza_core/mix.exs`: Product-core app for the Extravaganza proving-ground product
- `./apps/extravaganza_web/mix.exs`: Phoenix web shell app for the Extravaganza umbrella
- `./mix.exs`: Umbrella repo for the Extravaganza proving-ground product

# AGENTS.md

## Onboarding

Read `ONBOARDING.md` first for the repo's one-screen ownership, first command,
and proof path.

## Temporal developer environment

Temporal CLI is implicitly available on this workstation as `temporal` for local durable-workflow development. Do not make repo code silently depend on that implicit machine state; prefer explicit scripts, documented versions, and README-tracked ergonomics work.

## Native Temporal development substrate

When Temporal runtime behavior is required, use the stack substrate in `/home/home/p/g/n/mezzanine`:

```bash
just dev-up
just dev-status
just dev-logs
just temporal-ui
```

Do not invent raw `temporal server start-dev` commands for normal work. Do not reset local Temporal state unless the user explicitly approves `just temporal-reset-confirm`.

## Dependency Sources

- Dependency source selection is handled by `build_support/dependency_sources.exs` and `build_support/dependency_sources.config.exs`.
- Local dependency overrides use `.dependency_sources.local.exs`.
- Dependency source selection must not use environment variables.
- Same-repo umbrella package paths may stay in their local `mix.exs` files; cross-repo dependencies that need fallback behavior belong in the dependency-source manifest.
- Weld maintains helper drift, manifests, clone checks, publish checks, and publish order, but this repo is not a Weld consumer in this pass and must not receive a blind Weld dependency.

## Runtime Env

- Runtime application code under `lib/**`, package `lib/**`, example `lib/**`, and Mix task modules must not call direct OS env APIs such as `System.get_env`, `System.fetch_env`, `System.put_env`, or `System.delete_env`.
- Runtime/deployment env reads belong in `config/runtime.exs` or a `Config.Provider`.
- Product commands, examples, and harnesses should accept explicit flags, app config, or caller-supplied env maps instead of reading or mutating process env.

## Live Provider Checks

For live checks, set provider credentials in the shell env and run the product
command paths directly. Do not print secret values.

- Linear examples: `LINEAR_API_KEY`
- Codex examples: `OPENAI_API_KEY` and `CODEX_API_KEY`
- GitHub examples: `GH_TOKEN` or `GITHUB_TOKEN`

Linear examples also accept `--api-key-stdin` when piping a key into the command
line for short local sessions. Live provider smoke is not product acceptance
unless it runs the product-owned Extravaganza command path.

<!-- gn-ten:repo-agent:start repo=extravaganza source_sha=ab276c0640772b73065ab12bf05d77be51f1bb67 -->
# extravaganza Agent Instructions Draft

## Owns

- Thin proving-product UX and operator journeys.
- Product defaults, product profiles, prompts/templates, and product pack
  authoring.
- Browser/API presentation through AppKit DTOs.

## Does Not Own

- Workflow engines.
- Runtime bridges.
- Generic governance.
- Lower execution.
- Connector credential handling.

## Allowed Dependencies

- AppKit product surfaces.
- Pure Mezzanine pack model contracts for product pack authoring only.

## Forbidden Imports

- Direct Mezzanine runtime services.
- Citadel internals.
- Jido Integration internals.
- Execution Plane modules.
- Provider SDK clients for governed work.

## Verification

- `mix ci`
- `mix app_kit.no_bypass --root . --profile product --profile hazmat`

## Escalation

If product work needs a platform capability, add an AppKit surface or lower
contract instead of importing the lower repo.
<!-- gn-ten:repo-agent:end -->
