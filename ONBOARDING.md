# extravaganza Onboarding

Read `AGENTS.md` first; the managed gn-ten section is the repo contract.
`CLAUDE.md` must stay a one-line compatibility shim containing `@AGENTS.md`.

## Owns

Thin proving-product UX, operator journeys, product defaults, product profiles,
prompt/templates, product pack authoring, and browser/API presentation.

## Does Not Own

Workflow engines, runtime bridges, generic governance, lower execution,
connector credential handling, or reusable product-boundary mechanics.

## First Task

```bash
cd /home/home/p/g/n/extravaganza
mix ci
cd /home/home/p/g/n/stack_lab
mix gn_ten.plan --repo extravaganza
```

## Proofs

StackLab owns assembled proof. Use `/home/home/p/g/n/stack_lab/proof_matrix.yml`
and `/home/home/p/g/n/stack_lab/docs/gn_ten_proof_matrix.md`.

## Common Changes

Go through AppKit for platform behavior. If product work needs a missing
platform capability, add the AppKit seam or lower contract first.
