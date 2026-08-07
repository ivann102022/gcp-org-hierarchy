<!--
File:        docs/adr/README.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Index of Architecture Decision Records for gcp-org-hierarchy.
             Format: MADR-lite (Status / Context / Decision / Consequences
             / Alternatives / References). One ADR per non-obvious decision.
-->

# Architecture Decision Records

This directory holds the ADRs for `gcp-org-hierarchy`. Each ADR documents one non-obvious architectural decision &mdash; the problem context, the chosen option, the tradeoffs, and the alternatives that were rejected.

**Format**: MADR-lite (see any existing ADR for the template).
**Numbering**: 4-digit sequential (`0001-`, `0002-`, ...). Numbers are never reused, even if an ADR is superseded.
**Status values**: `Proposed` &vert; `Accepted` &vert; `Superseded by ADR-XXXX` &vert; `Deprecated`.
**When to write one**: any decision where a reader would ask "but why not the other way?" &mdash; tier boundary, mode choice, resource ownership, exclusion of an obvious feature, etc. Skip trivial conventions (naming, priorities) &mdash; those live in [`../conventions.md`](../conventions.md).

## Index

| # | Title | Status | Date |
|---|---|---|---|
| [0001](0001-two-modes-only-existing-and-create.md) | Two organization modes only (`existing` / `create`), no `blueprint` or `control_tower` equivalent | Accepted | 2026-08-07 |
| [0002](0002-platform-projects-here-not-in-lz.md) | Platform projects (`plogs` / `pmgm` / ...) are created here, not by each landing zone | Accepted | 2026-08-07 |
| [0003](0003-org-sink-in-tier0-not-obs-baseline.md) | Organization-level log sink lives in Tier 0, not in the observability baseline | Accepted | 2026-08-07 |
| [0004](0004-no-workforce-identity-federation-here.md) | Workforce Identity Federation is not in Tier 0 &mdash; it belongs in the identity baseline | Accepted | 2026-08-07 |
