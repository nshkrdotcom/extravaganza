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

Credential-free source fixture helpers live under test support only. Production
Linear/GitHub/Codex integrations enter below the product boundary through
AppKit, Mezzanine, and Jido Integration.
