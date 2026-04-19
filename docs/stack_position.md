# Stack Position

Extravaganza is not intended to be a new platform core.

It is the first place where the integrated stack is assembled into a coherent
product surface:

```text
Extravaganza
  -> app_kit thin surfaces
      -> mezzanine bridges and northbound surfaces
          -> Citadel / outer_brain / jido_integration
              -> execution_plane
```

The repo should prove the end-user and operator experience while resisting the
temptation to absorb lower reusable machinery.

The phase-3 proof target is stricter than thin composition: product runtime code
must not bypass AppKit for governed writes, lower reads, review actions, trace
lookup, semantic assist, or execution effects. `mix ci` runs the AppKit
no-bypass scanner so that this is an enforced boundary instead of a convention.
