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
- `Extravaganza.LinearIntakeAdapter` for Linear-originated work ingestion
- `Extravaganza.ProductHost` for product-local AppKit entrypoints backed by
  the current northbound bridge path

The product does not own a workflow compiler, review engine, planner, or
runtime bridge. Those concerns stay below the product boundary.

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
- Linear issue normalization into `AppKit.WorkSurface`
- thin-host run start through `AppKit.WorkControl`
- operator projection access through `AppKit.OperatorSurface`

The next major layer is the product operator shell.

## Boot Flow

```text
Application start
  -> Extravaganza.BootstrapWorker
      -> Extravaganza.ProductBootstrap
          -> AppKit.InstallationSurface

Linear issue
  -> Extravaganza.LinearIntakeAdapter
      -> AppKit.WorkSurface

Product-host run
  -> Extravaganza.ProductHost
      -> AppKit.WorkControl / AppKit.OperatorSurface
      -> Mezzanine.AppKitBridge
      -> Mezzanine services
```

## Development

The project targets Elixir `~> 1.19` and Erlang/OTP `28`.

```bash
mix deps.get
mix ci
```

See also:

- [Overview](docs/overview.md)
- [Stack Position](docs/stack_position.md)
- [Product Direction](docs/product_direction.md)
- [Product Profile](docs/product_profile.md)
