# Overview

Extravaganza is the proving-ground product application for the nshkr stack.

The repo stays thin by owning only product-level composition:

- product defaults and configuration
- durable program bootstrap
- product-specific intake normalization
- product-specific host entrypoints
- future operator-facing shell and journey design

Reusable business semantics, configurable workflow machinery, and generalized
operational models live in `mezzanine`.
