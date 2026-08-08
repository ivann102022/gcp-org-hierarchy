<!--
File:        docs/adr/README.md
Author:      Ismael Cruz
Version:     0.4.0
Description: Index of Architecture Decision Records for gcp-org-hierarchy.
             Format: MADR-lite + v0.3.0 enrichment sections (Rationale /
             Trade-offs / Controls this decision supports / Maturity path)
             on decisions where the framing applies. See ../security/ for
             the consolidated framework mapping and maturity roadmap.
-->

# Architecture Decision Records

This directory holds the ADRs for `gcp-org-hierarchy`. Each ADR documents one non-obvious architectural decision &mdash; the problem context, the chosen option, the tradeoffs, and the alternatives that were rejected.

## Format

**Base format**: MADR-lite (see any existing ADR for the template):
- Status
- Context
- Decision
- Consequences (positive / negative / neutral)
- Alternatives considered
- References

**Enrichment sections added in v0.3.0** on ADRs where the decision touches security architecture or has a natural evolution:
- **Rationale** &mdash; separates the *why* from the *what*, especially where the decision has multi-layer justification.
- **Trade-offs** &mdash; explicit trade-off statements (distinct from Consequences), naming what I sacrifice and consciously accept.
- **Controls this decision supports** &mdash; framework mapping with hedged language. Detailed mapping consolidated in [`../security/control-mapping.md`](../security/control-mapping.md).
- **Maturity path** &mdash; current implementation / enhanced / high-isolation option for the decision. Full portfolio-level roadmap in [`../security/maturity.md`](../security/maturity.md).

**Voice**: 1st person where the reasoning is experiential ("in my prior deployments...", "I chose this because..."). Impersonal where the text describes a GCP resource or a mechanical convention.

**Numbering**: 4-digit sequential (`0001-`, `0002-`, ...). Numbers are never reused, even if an ADR is superseded.
**Status values**: `Proposed` &vert; `Accepted` &vert; `Superseded by ADR-XXXX` &vert; `Deprecated`.
**When to write one**: any decision where a reader would ask "but why not the other way?" &mdash; tier boundary, mode choice, resource ownership, exclusion of an obvious feature, folder shape, cross-tier interlock, perimeter model, curated catalog choices, dry-run defaults, etc.

## Framework language convention

Across all ADRs and in [`../security/control-mapping.md`](../security/control-mapping.md):

- **"Supports controls typically found in ..."** &mdash; the decision provides a technical capability aligned with a framework area.
- **"Contributes to the implementation of ..."** &mdash; the decision is part of, but not sufficient for, meeting a specific control.
- **"Compliant with ..."** &mdash; **never used in portfolio documentation**. Reserved for statements backed by an actual audit or certification.

Framework references name **the area / family / category** rather than pinning exact clause numbers (which change across framework versions). Before quoting specific IDs externally, verify against the current published version.

## Index

| # | Title | Status | Date |
|---|---|---|---|
| [0001](0001-two-modes-only-existing-and-create.md) | Two organization modes only (`existing` / `create`), no `blueprint` or `control_tower` equivalent | Accepted (updated for v0.2.0 anchor+baseline note) | 2026-08-07 |
| [0002](0002-platform-projects-here-not-in-lz.md) | Platform projects (`plogs` / `pmgm` / ...) are created here, not by each landing zone | Accepted (v0.3.0 controls) | 2026-08-07 |
| [0003](0003-org-sink-in-tier0-not-obs-baseline.md) | Organization-level log sink lives in Tier 0, not in the observability baseline | Accepted (v0.3.0 controls, v0.4.0 IAM-ownership update) | 2026-08-07 |
| [0004](0004-no-workforce-identity-federation-here.md) | Workforce Identity Federation is not in Tier 0 &mdash; it belongs in the identity baseline | Accepted (v0.3.0 controls) | 2026-08-07 |
| [0005](0005-folder-per-platform-project.md) | One folder per platform project under `Platform` (1:1) | Accepted (v0.3.0 rationale + controls + maturity) | 2026-08-07 |
| [0006](0006-landing-zones-hostprj-serviceprj-env-split.md) | `LandingZones` sub-tree &mdash; `HUB` flat + `HostPrj` / `ServicePrj` with environment sub-folders | Accepted (v0.3.0 3-reasons rationale + controls + maturity) | 2026-08-07 |
| [0007](0007-content-rule-for-org-baseline.md) | Content rule for stack `00-org-baseline` &mdash; org-scope + fundacional + not-a-discipline | Accepted | 2026-08-07 |
| [0008](0008-ingress-bypasses-perimeter-appliance.md) | Public ingress bypasses the perimeter appliance by design | Accepted (v0.3.0 controls + maturity) | 2026-08-07 |
| [0009](0009-layered-segmentation-hierarchy-first.md) | Layered segmentation &mdash; hierarchy is the first line, not the network | Accepted | 2026-08-08 |
| [0010](0010-single-shared-perimeter-hub.md) | Single shared perimeter HUB across environments (economic + architectural rationale) | Accepted | 2026-08-08 |
| [0011](0011-curated-org-policy-catalog.md) | Curated org-policy catalog (8 policies) with dry-run-first default | Accepted | 2026-08-08 |
| [0012](0012-org-sink-design.md) | Org sink design &mdash; filter, destination, include_children, IAM binding ownership | Accepted | 2026-08-08 |
| [0013](0013-break-glass-user-model.md) | Break-glass model for org-scope IAM | Accepted | 2026-08-08 |
| [0014](0014-tag-catalog-choice.md) | Tag catalog choice and opt-in default | Accepted | 2026-08-08 |

## Related documents

- [`../security/control-mapping.md`](../security/control-mapping.md) &mdash; consolidated decision &times; framework matrix.
- [`../security/maturity.md`](../security/maturity.md) &mdash; per-decision current / enhanced / high-isolation roadmap.
- [`../architecture.md`](../architecture.md) &mdash; overall architecture narrative referencing every ADR.
- [`../contract.md`](../contract.md) &mdash; output contract consumed by baselines + LZs.
