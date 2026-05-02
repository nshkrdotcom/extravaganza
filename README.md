<p align="center">
  <img src="assets/extravaganza.svg" width="200" height="200" alt="Extravaganza logo" />
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/extravaganza/actions/workflows/ci.yml">
    <img alt="GitHub Actions Workflow Status" src="https://github.com/nshkrdotcom/extravaganza/actions/workflows/ci.yml/badge.svg" />
  </a>
  <a href="https://github.com/nshkrdotcom/extravaganza/blob/main/LICENSE">
    <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-0b0f14.svg" />
  </a>
</p>

# Extravaganza

Extravaganza is the first proving-ground product application for the nshkr
stack. It is an Elixir/OTP umbrella (`extravaganza_core` + `extravaganza_web`)
that stays intentionally thin: its job is to prove a coherent operator surface
above `app_kit` while pushing all reusable business semantics, workflow
machinery, and configurable operational logic down into `mezzanine`.

Extravaganza is the enterprise distributed port of the
[OpenAI Symphony](https://github.com/openai/symphony) headless coding-agent
orchestration pattern. Symphony defines a language-agnostic service that
continuously reads work from an issue tracker, creates isolated per-issue
workspaces, and drives a coding agent session for each item. Extravaganza ports
that concept onto the nshkr substrate: Temporal-backed durable workflows,
multi-tenant authorization, operator review gates, evidence collection, and
structured audit trails replace Symphony's intentionally simple in-memory
single-node design.

## Stack position

```
Extravaganza          ← this repo: product UX, operator journeys, pack authoring
  └─ app_kit          ← northbound surfaces, governed product boundary
       └─ mezzanine   ← reusable business engines, Temporal-backed workflows
            └─ citadel / outer_brain / jido_integration
                 └─ execution_plane
```

`app_kit` is the only allowed entry point for governed product behavior.
Extravaganza's sole direct Mezzanine coupling is the pure `Mezzanine.Pack`
model contract used to author its product pack. Everything else — bootstrap,
intake, operator queue/detail, review decisions, pause/resume/cancel, trace
lookup, semantic assist, source publication, and lower read leases — goes
through typed `AppKit.*` surfaces.

The CI gate (`mix app_kit.no_bypass`) enforces this boundary continuously with
both `product` and `hazmat` profiles so it is a hard rule, not a convention.

## What this repo owns

- Product UX and operator journeys
- Product identity, configuration, and pack authoring
- Product defaults: policy bundle, work class, placement profile, source binding
- Product prompts and operator review workpad templates
- Safe defaults for local and single-user proving deployments
- `Extravaganza.ProductHost` — the unified product host facade

## What this repo does not own

- Workflow engines or runtime bridges
- Generic governance, review gating, or audit assembly
- Lower execution, connector credential handling, or source admission
- Reusable operational state models or business orchestration

## Product modules

| Module | Role |
|---|---|
| `Extravaganza.Config` | Normalized product configuration |
| `Extravaganza.ProductProfile` | Default install and routing profile |
| `Extravaganza.ProductPack` | `Mezzanine.Pack` manifest for the coding-ops workflow |
| `Extravaganza.PolicyPresets` / `WorkClasses.*` | Product-owned policy and work-class defaults |
| `Extravaganza.ProductBootstrap` | Idempotent durable bootstrap via `AppKit.InstallationSurface` |
| `Extravaganza.ProductHost` | Operator facade over `AppKit.Work*`, `AppKit.OperatorSurface`, `AppKit.ReviewSurface` |
| `Extravaganza.CodingOpsTemplates` | Coding-agent system prompt and review workpad copy |

## Default product pack

The coding-ops product pack declares the intended Linear-backed Codex review
lane. Live governed Codex execution, source publication, runtime metrics, and
operator decision effects are not release claims until the owning phases add
executable proof.

| Dimension | Default |
|---|---|
| Program slug | `extravaganza_coding_ops` |
| Source binding | `linear_primary` (Linear → `coding_task` subjects) |
| Execution recipe | Codex session, 12-turn budget, 300 s stall timeout |
| Dynamic tools | `linear.comment.update`, `github.pr.create` |
| Review gate | Operator review, 72-hour window |
| Required evidence | `github_pr`, `codex_session`, `source_workpad` |
| Operator actions | pause, resume, cancel, request rework |
| Lifecycle | submitted → awaiting\_review → completed / rejected / expired |

ProductPack config names are bounded product inputs. The default pack accepts
only `coding_task` for `work_class_kind`, `linear` for `linear_source_kind`,
`coding_operations` for `work_class_name`, and `local_default` for
`placement_profile_id`; the derived source binding is the fixed
`linear_primary` ref. Unknown names raise before manifest refs are built, so
human-authored config cannot create BEAM atoms through ProductPack.

Source publication (the Linear workpad comment update) is an intended workflow
effect for subjects that enter `awaiting_review`. The write is owned by the
workflow/source-publisher path below AppKit; until that path has executable
proof, the product only renders the workpad body and reads deterministic
publication state through `AppKit.WorkSurface` projection DTOs.

## Boot flow

```
Application start
  └─ internal OTP bootstrap worker
       └─ Extravaganza.ProductBootstrap
            └─ AppKit.InstallationSurface

Product-host run
  └─ Extravaganza.ProductHost
       ├─ AppKit.WorkControl / AppKit.WorkSurface
       ├─ AppKit.OperatorSurface
       ├─ AppKit.ReviewSurface
       └─ Mezzanine.AppKitBridge  (owned by app_kit, not this repo)
```

Real Linear source events enter below the product boundary through Jido
Integration and Mezzanine source admission. Extravaganza owns source defaults
and credential-free test fixtures only.

## Development

Targets Elixir `~> 1.19` and Erlang/OTP `28`.

```bash
mix deps.get
mix ci
```

`mix ci` runs the full quality sequence:

1. `deps.get`
2. AppKit no-bypass boundary scan (`product` + `hazmat` profiles)
3. `format --check-formatted`
4. `compile --warnings-as-errors`
5. `test` (with `ash.setup`)
6. `credo --strict`
7. `dialyzer --force-check`
8. `docs --warnings-as-errors`

The boundary scan command run by CI:

```bash
mix app_kit.no_bypass --root . \
  --profile product \
  --profile hazmat \
  --include "apps/extravaganza_core/lib/**/*.ex" \
  --include "apps/extravaganza_web/lib/**/*.ex"
```

Oban is configured for Mezzanine's retained local duties only
(workflow-start outbox, workflow-signal outbox, claim-check GC). Live
orchestration state is projected from Mezzanine workflow facts through AppKit
surfaces; Extravaganza does not treat Oban as a durable workflow engine.

## Temporal development substrate

Temporal runtime development is managed from the `mezzanine` repo via its
`just` workflow. Do not start ad hoc Temporal processes.

```bash
cd /home/home/p/g/n/mezzanine
just dev-up        # start local Temporal dev server
just dev-status    # check health
just dev-logs      # tail logs
just temporal-ui   # open UI at http://127.0.0.1:8233
```

Local contract: `127.0.0.1:7233`, namespace `default`, persistent state at
`~/.local/share/temporal/dev-server.db`.

## Escalation path

If product work needs a platform capability that AppKit does not yet expose,
add the AppKit surface or lower contract first. Do not import lower platform
modules directly from product business code.

## Further reading

- [Overview](docs/overview.md)
- [Stack Position](docs/stack_position.md)
- [Product Direction](docs/product_direction.md)
- [Product Profile](docs/product_profile.md)
