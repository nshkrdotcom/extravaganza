# Product Profile

Extravaganza currently ships one default durable product profile.

## Default Program

- tenant id: configured per environment, default `extravaganza`
- program slug: `extravaganza_coding_ops`
- program family: `extravaganza`
- default intake source kind: `linear`

## Default Policy Bundle

- name: `default_coding_ops`
- kind: workflow markdown
- posture: manual approval, operator review required, local-affinity placement

## Default Work Class

- name: `coding_operations`
- kind: `coding_task`
- intake shape: Linear-style issue payload
- review posture: operator approval required
- run posture: Codex session execution

## Default Placement

- profile id: `local_default`
- strategy: `affinity`
- runtime driver preference: `jido_session`
- workspace posture: per-work strict sandbox

## Product Entry Paths

- durable bootstrap:
  `Extravaganza.ProductBootstrap -> AppKit.InstallationSurface`
- intake:
  `Extravaganza.LinearIntakeAdapter -> AppKit.WorkSurface`
- product-host run path:
  `Extravaganza.ProductHost -> AppKit.* -> Mezzanine.AppKitBridge`
  `AppKit` owns the governed northbound contract and lower bridge hydration
- review decisions:
  `Extravaganza.Reviews -> AppKit.ReviewSurface`
- operator controls:
  `Extravaganza.Operators -> AppKit.OperatorSurface`
- trace and readback:
  `Extravaganza.Operators -> AppKit.OperatorSurface`

## Ownership Boundary

Extravaganza owns:

- product defaults
- product composition
- future operator shell

Extravaganza does not own:

- workflow compilation
- work planning
- review gating
- audit assembly
- lower runtime dispatch
- lower facts readback
- execution-plane write paths

## AppKit Boundary Gate

`mix ci` runs the AppKit scanner over product source with the `product` and
`hazmat` profiles. The `product` profile blocks direct lower governed-write
imports while allowing the pure `Mezzanine.Pack` contract. The `hazmat` profile
separately blocks direct Execution Plane usage.
