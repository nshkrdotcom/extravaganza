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

Extravaganza should not own:

- generic business-semantic workflow machinery
- reusable operational state models
- lower runtime, connector, or execution concerns

## Status

Initial Elixir application scaffold. The long-term intent is a thin,
high-leverage proving ground that configures the reusable machinery built in
`mezzanine`.

## Development

The project targets Elixir `~> 1.19` and Erlang/OTP `28`.

```bash
mix deps.get
mix ci
```
