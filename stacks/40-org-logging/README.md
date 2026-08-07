<!--
File:        stacks/40-org-logging/README.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Placeholder for the org-logging stack — planned for v0.2.0.
             Not yet scaffolded with HCL.
-->

# Stack `40-org-logging` (planned v0.2.0)

`google_logging_organization_sink` at the Organization scope, pointing at the `plogs` project's `_Default` log bucket (or an override). Also owns the IAM binding on `plogs` for the sink's writer identity.

**Not yet implemented.** Scaffolded as an empty directory to reserve the stack number and document intent. Implementation lands in v0.2.0.

## Why in Tier 0 and not the observability baseline

Org-level log sink creation requires `roles/logging.configWriter` at the Organization scope. `gcp-observability-baseline` runs with project-scope permissions on `plogs` only. Putting the sink in the baseline would force it to hold org-scope IAM &mdash; violating least privilege. See [ADR-0003](../../docs/adr/0003-org-sink-in-tier0-not-obs-baseline.md).

## Planned outputs

- `log_sink_writer_identity` &mdash; consumed by `gcp-observability-baseline` when it grants the sink write access to log destinations inside `plogs`.
- `log_sink_destination` &mdash; full destination reference.

## Cross-references

- [../../docs/architecture.md](../../docs/architecture.md) &mdash; section "Why the org log sink lives here, not in observability-baseline".
- [../../docs/adr/0003-org-sink-in-tier0-not-obs-baseline.md](../../docs/adr/0003-org-sink-in-tier0-not-obs-baseline.md).
