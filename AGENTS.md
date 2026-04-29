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
