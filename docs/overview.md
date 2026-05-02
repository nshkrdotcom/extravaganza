# Overview

Extravaganza is the proving-ground product application for the nshkr stack.

The repo stays thin by owning only product-level composition:

- product defaults and configuration
- durable program bootstrap
- product-specific source defaults
- product-specific host entrypoints
- future operator-facing shell and journey design

Reusable business semantics, configurable workflow machinery, and generalized
operational models live in `mezzanine`.

The product consumes those lower capabilities only through AppKit. Runtime
bootstrap, intake, operator queue/detail, review decisions, pause/resume/cancel,
trace lookup, semantic assist, and read/stream leases are product-facing AppKit
calls. Extravaganza's only direct Mezzanine coupling is the pure
`Mezzanine.Pack` model contract used to author its product pack.

Extravaganza owns the coding-ops prompt and operator review workpad templates.
It renders source-publication preview/readback from AppKit runtime projection
DTOs. Actual source publication writes remain workflow-owned below AppKit and
use refs carried by source admission, workflow state, provider create/list
output, or durable receipts.

Credential-free source fixture helpers live under test support only. Production
Linear/GitHub/Codex integrations enter below the product boundary through
AppKit, Mezzanine, and Jido Integration.

The v1 release claim is deterministic. It covers the governed product boundary,
ProductPack bounds, authoring-bundle activation, tenant and authority
admission, governed Codex strict-mode materialization, deterministic receipt
projection, governed operator controls, and restart/fencing proof. It does not
claim live Linear, GitHub, or Codex execution until disposable-auth smoke runs
through the governed path.
