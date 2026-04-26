# Product Profile

Extravaganza currently ships one default durable product profile.

## Default Program

- tenant id: configured per installation, default `extravaganza`
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

## Default Source Binding

- binding ref: `linear_primary`
- provider: `linear`
- source kind: `linear`
- state mapping: submitted/backlog, review, retry, completed, rejected, and expired
- source publish: update the existing Linear workpad comment when work enters review

## Default Prompt And Workpad

- prompt ref: `coding_agent_system`
- workpad template ref: `operator_review_workpad`
- prompt and workpad copy live in `Extravaganza.CodingOpsTemplates`
- provider identity is read from source admission, provider create/list output,
  workflow state, or durable receipts
- the product renders source-publication preview/readback from
  `AppKit.Core.SubjectRuntimeProjection`; it does not write provider source
  comments directly

## Default Placement

- profile id: `local_default`
- strategy: `affinity`
- runtime driver preference: `jido_session`
- workspace posture: per-work strict sandbox

## Default Runtime Policy

- workspace root ref: `extravaganza_workspaces`
- sandbox policy ref: `standard_coding_ops`
- prompt refs: `coding_agent_system`
- dynamic tools: Linear comment update and GitHub PR create
- turn budget: 12
- stall timeout: 300 seconds

## Default Review And Evidence Policy

- review gate: `operator_review`
- required evidence kinds: `github_pr`, `codex_session`, and `source_workpad`
- allowed review decisions: accept, reject, waive, and expire
- source workpad evidence is collected when the subject enters review
- GitHub PR and Codex session evidence is collected from execution completion
  receipts

## Default Operator Actions

- pause execution while submitted, in review, or awaiting retry
- resume execution while submitted, in review, or awaiting retry
- cancel the active execution while submitted, in review, or awaiting retry
- request rework from review

## Product Entry Paths

- durable bootstrap:
  `Extravaganza.ProductBootstrap -> AppKit.InstallationSurface`
- credential-free fixture ingest:
  `Extravaganza.TestSupport.LinearIssueFixture -> AppKit.WorkSurface`
- product-host run path:
  `Extravaganza.ProductHost -> AppKit.* -> Mezzanine.AppKitBridge`
  `AppKit` owns the governed northbound contract and lower bridge hydration
- runtime projection and workpad readback:
  `Extravaganza.ProductHost -> AppKit.WorkSurface.get_runtime_projection/3`
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

Real Linear provider admission is intentionally outside the active product code
path. It belongs to the Jido Integration connector and Mezzanine source
admission lane; Extravaganza owns source defaults and test-only fixture helpers.
