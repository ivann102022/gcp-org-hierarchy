<!--
File:        docs/adr/0001-two-modes-only-existing-and-create.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0001: Two organization modes only (`existing` / `create`), no `blueprint` or `control_tower` equivalent

**Status**: Accepted
**Date**: 2026-08-07
**Deciders**: Ismael Cruz
**Tags**: gcp, tier-0, modes, cloud-foundation-fabric

## Context

The sibling repo `aws-org-hierarchy` supports three modes: `existing`, `create`, and `control_tower`. The `control_tower` mode exists because AWS Control Tower is a Google-, AWS- or Azure-provided runtime that stands as a **peer** to Terraform &mdash; both write to real infrastructure, both have opinions about the shape of the Organization, and Terraform has to explicitly hand off ownership of certain resources (`aws_controltower_landing_zone` enrols the Org; CT-managed OUs are read via data source).

The natural question in GCP: is there an equivalent of Control Tower that would justify a third mode?

The candidates:

1. **Google Cloud Foundation Fabric** &mdash; a set of opinionated Terraform blueprints published by Google (`terraform-google-modules/cloud-foundation-fabric`). Widely used as a starting point for enterprise GCP foundations.
2. **Google Cloud Setup / Landing Zone tool** &mdash; a console wizard that provisions a starter foundation.
3. **Assured Workloads** &mdash; a compliance-oriented service that wraps folders under a compliance regime; not a foundation tool.

## Decision

Ship v0.1.0 with **two modes only**: `existing` (data source everything) and `create` (Terraform provisions folders and platform projects).

No `blueprint` mode, no `foundation` mode, no `assured_workloads` mode in v0.1.0.

## Consequences

**Positive**:

- Simpler mental model &mdash; the two-value validation matches what actually differs behaviourally (are we reading, or are we writing?).
- No confusing "hybrid" mode where Terraform sometimes owns a resource and sometimes doesn't, gated on whether Fabric was applied first.
- Faster to ship v0.1.0: two modes fit inside a single conditional per resource block.

**Negative**:

- Customers running Fabric today must translate Fabric-provisioned folders / projects into the `existing` mode inputs manually. There is no auto-detection.
- If Google introduces a Control-Tower-equivalent runtime in the future, adding it as a third mode is a MINOR version bump (backwards-compatible: existing consumers unaffected).

**Neutral**:

- Documentation is clearer: two modes, one contract, same outputs. Consumers do not need to write `if mode == "..."` logic anywhere.

## Alternatives considered

**A. Ship v0.1.0 with a `blueprint` mode that consumes Fabric outputs.**
Rejected: Fabric is Terraform code, not a runtime. A `blueprint` mode would either (a) hard-code assumptions about which Fabric modules were used (fragile) or (b) devolve into `existing` mode with a different name. If the customer is running Fabric, `existing` mode already works &mdash; they pass in the folder / project IDs Fabric produced.

**B. Ship v0.1.0 with an `assured_workloads` mode.**
Rejected: Assured Workloads applies to specific folders and specific compliance regimes (FedRAMP, IL4, HIPAA, ...). Wrapping it in a Tier 0 mode overloads Tier 0 with compliance-tier concerns. If AW is needed, it lands as an opt-in feature on `10-folders` (`google_assured_workloads_workload` per-folder), not as a mode.

**C. Copy the AWS `control_tower` mode name and leave it as a no-op stub in GCP.**
Rejected: name collision breeds confusion. Better to omit than to ship a mode that does nothing.

## References

- [`../architecture.md`](../architecture.md) &mdash; per-stack mode gating.
- [`../conventions.md`](../conventions.md) &mdash; `organization_mode` variable spec.
- Sibling repo [aws-org-hierarchy `docs/architecture.md`](../../../aws-org-hierarchy/docs/architecture.md) &mdash; the three-mode design this ADR deliberately does not mirror.
- [Google Cloud Foundation Fabric](https://github.com/GoogleCloudPlatform/cloud-foundation-fabric) &mdash; the blueprint set this repo intentionally does not integrate with as a mode.
