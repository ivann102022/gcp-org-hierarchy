<!--
File:        docs/adr/0003-org-sink-in-tier0-not-obs-baseline.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0003: Organization-level log sink lives in Tier 0, not in the observability baseline

**Status**: Accepted
**Date**: 2026-08-07
**Deciders**: Ismael Cruz
**Tags**: gcp, tier-0, tier-1, observability, org-scope-iam, blast-radius

## Context

Every enterprise GCP foundation ends up with a **single organization-level log sink** that fans out logs from every project in the Org to a centralized destination (typically the `plogs` project's `_Default` log bucket, or a BigQuery dataset, or Pub/Sub). The resource is `google_logging_organization_sink` and it requires the executing identity to hold `roles/logging.configWriter` **at the Organization scope**.

The obvious place for "logging infrastructure" is `gcp-observability-baseline` (Tier 1). But observability-baseline is written to run **inside a single project** (`plogs`) with project-scope permissions &mdash; it configures log buckets, retention, exclusions, exports, dashboards, alerts. All project-scoped operations.

Putting the org sink in observability-baseline would force the baseline to hold `roles/logging.configWriter` at the Organization scope, which:

- Violates least privilege (the baseline needs org-scope rights only for the sink; nothing else it does needs org-scope).
- Creates a cross-tier privilege escalation surface (a compromise of the observability CI/CD SA gains org-scope logging config).
- Makes the baseline non-runnable in customer environments where the org-scope role is delegated to a Foundation SA only.

## Decision

**The `google_logging_organization_sink` resource lives in Tier 0**, stack `40-org-logging` (planned v0.2.0). Tier 0's SA already holds org-scope roles; adding `roles/logging.configWriter` to it is a natural extension.

Split of ownership:

| Concern | Owner | Rationale |
|---|---|---|
| `google_logging_organization_sink` (creation, filter, destination pointer) | Tier 0 (`gcp-org-hierarchy`) | Org-scope resource; only Tier 0 SA holds the right role. |
| IAM binding on `plogs` for the sink's `writer_identity` | Tier 0 (`gcp-org-hierarchy`) | Sink + writer identity are one atomic concern. |
| Log buckets, retention policies, exclusions inside `plogs` | Tier 1 (`gcp-observability-baseline`) | Project-scope operations; baseline holds `roles/logging.admin` on `plogs` only. |
| Exports (BigQuery, Pub/Sub, GCS) fed by the sink | Tier 1 (`gcp-observability-baseline`) | Project-scope destinations. |
| Dashboards, alerts on the aggregated logs | Tier 1 (`gcp-observability-baseline`) | Cloud Monitoring workspace attached to `plogs`. |

Tier 0's contract exposes `log_sink_writer_identity` and `log_sink_destination` as outputs (v0.2.0), which observability-baseline reads via `terraform_remote_state` and uses to configure the receiving bucket / dataset.

## Consequences

**Positive**:

- Observability-baseline stays project-scoped &mdash; runnable with a project-scoped SA only.
- Org-scope rights concentrated in Tier 0 SA (which is used sparingly &mdash; once per hierarchy change, never per baseline change).
- Blast radius: a bug in observability-baseline cannot break org-wide log routing.
- Matches the ownership pattern of the AWS sibling: `aws-org-hierarchy` owns `aws_organizations_delegated_administrator` for CloudTrail / GuardDuty (org-scope), and `aws-lz-guardrails` owns the actual service configuration (account-scope).

**Negative**:

- Bootstrapping a new customer requires Tier 0 to be applied through stack `40-org-logging` before observability-baseline can run. Not a real cost &mdash; Tier 0 is applied first anyway.
- Two remote-state reads for observability-baseline: one to Tier 0 (`40-org-logging` for the writer identity), one within its own state. Documented in the baseline's README.

**Neutral**:

- Writer identity IAM binding has a known propagation lag &mdash; first apply of the binding after the sink is created can fail with "principal not found" and needs a re-apply after ~30 seconds. Documented as a failure mode in [`../architecture.md`](../architecture.md).

## Alternatives considered

**A. Put the org sink in `gcp-observability-baseline`.**
Rejected: forces the baseline to hold org-scope IAM, violating least privilege and coupling the baseline's blast radius to org-wide logging. See Context.

**B. Create a dedicated `gcp-org-logging` repo.**
Rejected: one resource + one IAM binding does not warrant a repo. The natural home is Tier 0 because Tier 0 already holds org-scope permissions and its lifecycle (change rarely, high blast radius) matches the sink's.

**C. Manage the org sink outside Terraform (console / gcloud one-shot).**
Rejected: portfolio-wide policy is IaC-only. A manually-created sink drifts silently and is not reproducible.

## References

- [`../architecture.md`](../architecture.md) &mdash; section "Why the org log sink lives here, not in observability-baseline".
- [`../contract.md`](../contract.md) &mdash; `log_sink_writer_identity` and `log_sink_destination` output spec (v0.2.0).
- [GCP: Aggregated sinks](https://cloud.google.com/logging/docs/export/aggregated_sinks) &mdash; canonical reference for org-scope sinks and the writer identity IAM pattern.
