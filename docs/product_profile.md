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
  `Extravaganza.ProductBootstrap -> Mezzanine.Surfaces.ProgramSurface`
- intake:
  `Extravaganza.LinearIntakeAdapter -> Mezzanine.Surfaces.WorkSurface`
- thin-host run path:
  `Extravaganza.ThinHost -> AppKit.* -> Mezzanine.AppKitBridge`

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
