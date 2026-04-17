# Product Direction

The long-term direction is a high-trust operator surface for globally
distributed AI operations.

That means:

- a thin product shell here
- a large reusable business and orchestration substrate in `mezzanine`
- lower execution, runtime, and connector effects pushed downward into the
  existing stack

Extravaganza should become the reference proving deployment for the broader
system, not the home for generic infrastructure.

Current composition rules:

- use `Mezzanine.Surfaces.*` for durable product semantics
- use `AppKit.*` only through thin generic northbound surfaces
- do not call `jido_integration` directly from product business code
- keep policy, work-class, and placement choices product-owned, but keep the
  engines that interpret them below the product boundary
