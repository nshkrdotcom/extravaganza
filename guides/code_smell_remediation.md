# Extravaganza Code Smell Remediation

This guide records the product-local implementation posture after the GN-TEN
code smell remediation pass.

## What Changed

- Headless live examples keep product-facing Linear/GitHub/Codex vocabulary,
  but governed calls enter through AppKit and the generic stack.
- CLI dispatch responsibilities are split so descriptors, execution,
  credentials, and presentation are not owned by one module.
- Runtime fixture installation uses scoped helpers rather than leaking
  application-env mutations across tests.
- Blocking web task behavior is owned by supervised OTP lifecycle paths.
- Default fixture builders and Symphony import logic are kept product-owned
  and are documented as product migration/parity surfaces.

## Live Provider Verification

Live provider checks must run through the product command surface. On the
shared workstation, load secrets by prepending commands with
`~/scripts/with_bash_secrets`.

```bash
~/scripts/with_bash_secrets bash -lc 'printf "%s" "$LINEAR_API_KEY" | mix extravaganza.headless.live.smoke --live-product-path --ack-headless-guardrails --json --api-key-stdin --assignee all --issue-id LINEAR_ISSUE_UUID --issue-ids LINEAR_ISSUE_UUID --repo OWNER/REPO --pull-number PR_NUMBER --ref HEAD_SHA'
```

## QC

Use the repo root gate:

```bash
mix ci
```
