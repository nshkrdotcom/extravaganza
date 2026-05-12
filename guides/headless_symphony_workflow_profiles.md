# Symphony Workflow Profiles

Extravaganza accepts a Symphony-style `WORKFLOW.md` as a product ingress
format through `Extravaganza.SymphonyWorkflowImport`. The importer preserves the
headless source behavior that belongs at the product boundary: explicit
workflow path selection, default `WORKFLOW.md` lookup from the supplied cwd,
YAML front matter parsing, prompt body extraction, strict prompt rendering, and
redacted profile readback.

Runtime/product code does not read ambient OS environment variables. A caller
that wants Symphony `$VAR` behavior must pass an explicit env map at command
ingress, for example `--env LINEAR_API_KEY=...`, or use a Config.Provider or
shell harness before calling the product command. The profile stores credential
refs such as `env://LINEAR_API_KEY`; it never stores or prints the secret value.

The product profile readback contains these layers:

- `workflow`: selected path, prompt template, and prompt hash.
- `config`: normalized tracker, polling, workspace, worker, agent, Codex,
  hooks, observability, and server settings.
- `runtime_profile`: compact product run settings used by Extravaganza
  readbacks.
- `app_kit_runtime_profile`: the AppKit/Mezzanine-shaped payload that can be
  supplied through `AppKit.InstallationSurface` context metadata. The AppKit
  Mezzanine bridge passes that payload to its runtime-profile service, which
  owns durable runtime profile semantics below the product shell.

`profile_reload` re-parses and validates the selected workflow. On a successful
reload it writes a redacted last-known-good profile cache and applies the
profile through `AppKit.RuntimeSurface`; the response includes
`runtime_profile_apply` and `runtime_profile_ref` readback fields. On a parse
or validation failure it reports `reload_failed` and returns the cached
last-known-good profile, matching Symphony's operator behavior of keeping the
previous valid workflow active.

Runtime status and log readbacks are exposed through `AppKit.RuntimeSurface`.
Governed source publication uses `AppKit.SourceSurface` through
`source_publish` and the `/api/v1/source-publication` route; Extravaganza does
not call lower Mezzanine runtime services or provider SDKs directly.

Reusable scheduling, workspace, provider, credential, and runtime mechanics do
not move into Extravaganza. Extravaganza imports the product-facing workflow
profile and exposes it through CLI/API; applying it to live work goes through
AppKit surfaces and the lower owning repos.
