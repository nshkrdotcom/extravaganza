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
- source publish intent: workflow-owned update of the existing Linear workpad
  comment when work enters review; v1 evidence covers deterministic projection
  and readback, not live Linear mutation

## Bounded ProductPack Names

ProductPack accepts only the shipped default config names when converting
human-authored product config into manifest refs:

| Config field | Accepted value | Manifest ref |
|---|---|---|
| `work_class_kind` | `coding_task` | `:coding_task` |
| `linear_source_kind` | `linear` | `:linear` |
| derived source binding | `linear` | `:linear_primary` |
| `work_class_name` | `coding_operations` | `:coding_operations` |
| `placement_profile_id` | `local_default` | `:local_default` |

Unknown names raise before refs are built. Future profile-slot inputs must use
the same explicit allowlist rule before they become human-authored config.

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
- dynamic tools: declared Linear comment update and GitHub PR create operations
  governed by connector manifests
- turn budget: 12
- stall timeout: 300 seconds

## Default Review And Evidence Policy

- review gate: `operator_review`
- required evidence kinds: `github_pr`, `codex_session`, and `source_workpad`
- allowed review decisions: accept, reject, waive, and expire
- source workpad evidence is collected when the subject enters review
- GitHub PR and Codex session evidence is collected from execution completion
  receipts

## Default Operator Controls

- accept review through AppKit and Mezzanine decision commands
- request rework from review through AppKit and Mezzanine decision commands
- cancel the active subject through AppKit and the Mezzanine operator-action owner path
- request source refresh through AppKit and the Mezzanine source-refresh owner path
- pause and resume remain product-policy declarations until an owning proof
  adds executable command evidence

## Product Entry Paths

- durable bootstrap:
  `Extravaganza.ProductBootstrap -> Extravaganza.DefaultAuthoringBundle -> AppKit.InstallationSurface.import_authoring_bundle/3`
  with `create_installation/2` used first when an active pack registration is
  already present
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
- default ProductPack seed compilation into an AppKit authoring-bundle import
  envelope

Extravaganza does not own:

- workflow compilation
- work planning
- review gating
- audit assembly
- lower runtime dispatch
- lower facts readback
- execution-plane write paths

Runtime policy authority belongs to the activated installation revision created
from the AppKit authoring-bundle import. `DefaultCodingOps.workflow_body/0` is
prompt/template text only; runtime settings are structured metadata on the
policy preset and must not activate by themselves.

## AppKit Boundary Gate

`mix ci` runs the AppKit scanner over product source with the `product` and
`hazmat` profiles. The `product` profile blocks direct lower governed-write
imports while allowing the pure `Mezzanine.Pack` contract. The `hazmat` profile
separately blocks direct Execution Plane usage.

Real Linear provider admission is intentionally outside the active product code
path. It belongs to the Jido Integration connector and Mezzanine source
admission lane; Extravaganza owns source defaults and test-only fixture helpers.

## v1 Release Evidence Boundary

The deterministic v1 release evidence covers ProductPack bounds, product
boundary no-bypass checks, authoring-bundle activation, tenant/authority
admission, governed Codex strict-mode materialization, deterministic receipt
projection, governed operator controls, and restart/fencing proof. Optional
live provider smoke was not run for v1, so this profile does not claim live
Linear, GitHub, or Codex execution.
