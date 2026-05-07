# Extravaganza Product No-Bypass

## Boundary

Extravaganza product code enters the platform through AppKit. The only direct lower coupling allowed in product source is the pure Mezzanine.Pack authoring contract. Boot configuration may name lower repos as application startup wiring, but product business code must not call lower store or runtime modules directly.

## Verification

Scan scope: `apps/**/lib/**/*.ex`. Command: `mix app_kit.no_bypass.scan --root /home/home/p/g/n/extravaganza --profile product --profile hazmat --include apps/**/lib/**/*.ex` from `/home/home/p/g/n/app_kit`.

## Owner Package Exclusions

A package may be excluded from product-surface scanning only when it owns the local store, connector adapter, or runtime integration being excluded. The package must document its adapter, default tier, durable opt-in, migration or preflight, allowed consumer surface, and redaction guarantees in package-local `docs/persistence.md`.

## Forbidden Product Imports

Product surfaces must not import lower runtime, lower store, trace writer, provider SDK, generated SDK, database repo, object store, or Temporal client modules directly. Add an AppKit surface or lower contract first.
