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
stack.

It is intentionally thin. The repo exists to prove a sophisticated operator
surface above `app_kit`, while pushing reusable business semantics, workflow
machinery, and configurable operational logic down into `mezzanine`.

## Product Core

The current product core is made of a small set of product-owned modules:

- `Extravaganza.Config` for normalized product config
- `Extravaganza.ProductProfile` for the default install and routing profile
- `Extravaganza.PolicyPresets` and `Extravaganza.WorkClasses.*` for product
  defaults
- `Extravaganza.ProductBootstrap` for idempotent durable bootstrap through
  `AppKit.InstallationSurface`
- `Extravaganza.ProductHost` for product-local AppKit entrypoints backed by
  the current northbound bridge path

The product does not own a workflow compiler, review engine, planner, or
runtime bridge. Those concerns stay below the product boundary.

The product boundary is AppKit. Extravaganza may author the pure
`Mezzanine.Pack` model contract for its product pack, but runtime bootstrap,
intake, queue/detail reads, reviews, operator pause/resume/cancel, trace lookup,
semantic assist, and lower-backed read leases all go through AppKit surfaces.
Direct product imports into Mezzanine runtime services, Citadel, Jido
Integration, or Execution Plane are not allowed.

## Stack Position

```text
operator product: Extravaganza
  -> northbound surfaces: app_kit
      -> host/kernel and semantic layers: Citadel + outer_brain
          -> integration/runtime plane: jido_integration
              -> lower execution and effect projection: execution_plane
```

Extravaganza should own:

- product-facing operator journeys
- product identity, packaging, and host composition
- safe defaults for local and single-user installs
- configuration and policy choices for a proving deployment
- product-specific program, placement, and work-class defaults

Extravaganza should not own:

- generic business-semantic workflow machinery
- reusable operational state models
- lower runtime, connector, or execution concerns
- duplicate business orchestration already provided by `mezzanine`

## Status

The repo now contains the first thin product-core slice:

- idempotent durable bootstrap into `mezzanine`
- credential-free source fixture coverage through `AppKit.WorkSurface`
- thin-host run start through `AppKit.WorkControl`
- operator projection access through `AppKit.OperatorSurface`
- review accept/reject/waive through `AppKit.ReviewSurface`
- operator pause/resume/cancel and unified/archived trace lookup through
  `AppKit.OperatorSurface`
- CI-enforced product and hazmat no-bypass scans via
  `mix app_kit.no_bypass`

Dependency health is current for the generalized Symphony lane. `erlexec` is
locked at `2.3.0`, satisfying the lower runtime dependency constraint, and the
root `mix ci` gate passes with format, compile, tests, no-bypass, Credo,
Dialyzer, and docs generation.

The next major layer is the product operator shell.

## Boot Flow

```text
Application start
  -> Extravaganza.BootstrapWorker
      -> Extravaganza.ProductBootstrap
          -> AppKit.InstallationSurface

Product-host run
  -> Extravaganza.ProductHost
      -> AppKit.WorkControl / AppKit.OperatorSurface
      -> Mezzanine.AppKitBridge
      -> Mezzanine services
```

Real Linear source events are not ingested by product-owned adapters. The
generalized Symphony lane routes provider source admission through Jido
Integration and Mezzanine source admission, with Extravaganza owning only
coding-ops source defaults and test fixtures for credential-free coverage.

## Development

The project targets Elixir `~> 1.19` and Erlang/OTP `28`.

```bash
mix deps.get
mix ci
```

`mix ci` runs the AppKit-owned boundary scanner before the normal quality
sequence:

```bash
mix app_kit.no_bypass --root . \
  --profile product \
  --profile hazmat \
  --include "apps/extravaganza_core/lib/**/*.ex" \
  --include "apps/extravaganza_web/lib/**/*.ex"
```

The gate requires product code to stay on AppKit for governed platform behavior
and separately proves there is no direct Execution Plane bypass.

Extravaganza does not treat Oban as a durable workflow engine. Product-host
configuration only permits Mezzanine's retained local Oban duties:
workflow-start outbox, workflow-signal outbox, and claim-check garbage
collection. Live orchestration state is projected from Mezzanine workflow facts
through AppKit surfaces.

See also:

- [Overview](docs/overview.md)
- [Stack Position](docs/stack_position.md)
- [Product Direction](docs/product_direction.md)
- [Product Profile](docs/product_profile.md)

## Temporal developer environment

Temporal CLI is expected to be available as `temporal` on this developer workstation for local durable-workflow development. Current provisioning is machine-level dotfiles setup, not a repo-local dependency.

TODO: make Temporal ergonomics explicit for developers by adding repo-local setup scripts, version expectations, and fallback instructions so the tool is not silently assumed from the workstation.

## Native Temporal development substrate

Temporal runtime development is managed from `/home/home/p/g/n/mezzanine` through the repo-owned `just` workflow, not by manually starting ad hoc Temporal processes.

Use:

```bash
cd /home/home/p/g/n/mezzanine
just dev-up
just dev-status
just dev-logs
just temporal-ui
```

Expected local contract: `127.0.0.1:7233`, UI `http://127.0.0.1:8233`, namespace `default`, native service `mezzanine-temporal-dev.service`, persistent state `~/.local/share/temporal/dev-server.db`.
