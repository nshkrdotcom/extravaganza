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

- use `AppKit.*` as the only governed product boundary
- allow direct `Mezzanine.Pack` use only for pure product pack authoring
- do not call `jido_integration` directly from product business code
- do not call Citadel, Mezzanine runtime services, or Execution Plane directly
  from product business code
- keep policy, work-class, and placement choices product-owned, but keep the
  engines that interpret them below the product boundary

The CI boundary gate enforces these rules through `mix app_kit.no_bypass` with
both `product` and `hazmat` profiles.
