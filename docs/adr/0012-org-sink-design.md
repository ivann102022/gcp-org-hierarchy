<!--
File:        docs/adr/0012-org-sink-design.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0012: Org sink design &mdash; filter, destination, include_children, and IAM binding ownership

**Status**: Accepted
**Date**: 2026-08-08
**Deciders**: Ismael Cruz
**Tags**: gcp, tier-0, logging, org-sink, plogs, obs-baseline-interlock

## Context

Stack `40-org-logging` provisions a single `google_logging_organization_sink` that captures every project's logs and routes them into the `plogs` project. Four design questions had to be answered:

1. **Filter**: what logs does the sink export?
2. **Destination**: where do the logs land inside `plogs`?
3. **`include_children`**: does the sink cover every folder / project, or only Org-scope?
4. **Writer-identity IAM binding**: who owns the IAM grant on `plogs` for the sink's writer SA &mdash; this stack, or `gcp-observability-baseline/00-log-storage` (which was designed with a deferred-integration hook because this stack didn't exist yet)?

Each answer is small, but the combination determines whether the org sink is a genuinely useful control or an expensive noise generator.

## Decision

### Filter: default `""` (all logs). Override for cost management.

The sink filter defaults to empty string (no filter &mdash; every log entry from every project in the Org is exported).

- **Rationale for empty default**: an org sink is designed to be the reliable central capture. Filtering at the sink is filtering **out** &mdash; anything filtered out never reaches `plogs` and cannot be queried later. For a first deployment I would rather have too many logs than realise mid-incident that the log I need was filtered out.
- **Cost management overrides**: prefer exclusion-based control (`var.exclusions`) over severity filtering. Severity is not a proxy for security-audit value &mdash; many security-relevant audit events (IAM changes, admin actions, SetIamPolicy calls) land at INFO or NOTICE severity, and a `severity>=WARNING` filter silently drops them. Use exclusions targeted at validated log classes (LB health checks, container liveness probes, well-known high-volume-low-value log names) rather than blanket severity thresholds. Resource-type filters (`resource.type="gce_instance" OR ...`) are also acceptable for use-case-specific captures.

### Destination: `_Default` bucket as bootstrap fallback; custom bucket as target architecture.

`destination_type = "log_bucket"` default; `destination_log_bucket = "_Default"` default (**bootstrap**); `destination_log_bucket_location = "global"` default.

**Important distinction &mdash; bootstrap fallback vs target architecture:**

- **Bootstrap fallback (`_Default`)**: the default value exists so this stack can be applied before `gcp-observability-baseline/00-log-storage` provisions a custom log bucket. The `_Default` bucket always exists in every project (Google-managed, 30-day retention, no CMEK, no Log Analytics upgrade). Zero prerequisite. Useful for greenfield bootstrap where the operator wants org sink capability immediately.
- **Target architecture (custom bucket)**: the intended long-term destination. Once obs-baseline's `00-log-storage` provisions the custom log bucket (`gcp0-log-bucket-default-01` by default), operators override `destination_log_bucket` to route there. Custom bucket has configured retention, CMEK, Log Analytics upgrade, exclusions catalog &mdash; capabilities `_Default` lacks. A deployment that stays on `_Default` past bootstrap is under-configured; it will fail an audit requiring retention beyond 30 days or encryption with a customer-managed key.

The default in Terraform does not prejudge which one applies to a given deployment. The operator makes the informed choice based on whether obs-baseline is applied yet. Documentation and this ADR treat custom bucket as target; `_Default` is the safe starting point.

**Non-log-bucket destinations** (BigQuery, Pub/Sub, GCS) are supported via `destination_type` + `destination_override` but are rare at the org sink level. Prefer per-destination sinks in `gcp-observability-baseline/10-log-exports` (which own their destinations) over doing everything at the org sink.

### Non-intercepting sink by default.

The stack does **not** set `intercept_children` on the sink. This is a deliberate choice, not an omission.

Two modes exist in GCP for aggregated org sinks:

- **Non-intercepting** (this stack's model): logs continue to be processed by their own project's `_Default` sink and by any other project- or folder-scoped sinks. This aggregated sink **additionally** captures them and routes centrally.
- **Intercepting** (via `intercept_children = true`): this sink pre-empts descendant sinks for the matching log classes. Descendant sinks that would otherwise receive those logs do not process them.

I chose non-intercepting because:

- **Central visibility does not need to break local project logging**. Workload teams often rely on the project's own log bucket for day-to-day operations; intercepting would silently remove that visibility.
- **The org sink is a copy-and-route control, not a policy control**. Making it authoritative over what descendant sinks can see would blur its role from "aggregation" to "enforcement".
- **Least surprise**: an operator who enables this stack is unlikely to expect that project-level logging behaviour changes as a side effect. Intercepting would produce exactly that side effect.

If an operator has a specific need for interception (e.g. compliance-scoped isolated logs that must not appear in workload team buckets), that's a `custom_sinks` variant in a future release &mdash; not the default behaviour of the central sink.

### `include_children = true` default.

The whole point of an org sink is to aggregate every project in every folder. `include_children = false` would only capture logs written at Org scope (near-zero volume in practice). Almost every deployment wants `true`.

Left as a variable in case someone genuinely wants Org-scope only (rare &mdash; maybe a debugging exercise on the Org's own audit logs).

### Writer-identity IAM binding: this stack owns it (default).

`google_project_iam_member.writer_identity` grants the sink's writer SA `roles/logging.bucketWriter` on `plogs`. Default `create_writer_identity_binding = true`.

- **Rationale**: the sink and its writer identity IAM are one atomic operational unit. If Terraform creates the sink but not the IAM, the sink writes fail silently. Splitting ownership across two repos means a partial apply leaves the customer in a bad state.
- **Interlock with obs-baseline**: `gcp-observability-baseline/00-log-storage` v0.1.0 has a deferred-integration hook (`var.org_sink_writer_identity`) that creates the same binding. This existed because Tier 0 stack `40-org-logging` didn't exist when obs-baseline was shipped. Once this stack ships (Tier 0 v0.4.0), the recommended transition is: keep the binding here (default), disable the obs-baseline hook (`org_sink_writer_identity = ""`). Interim: both stacks bind the SA &mdash; `google_project_iam_member` is idempotent at the API level; the effective policy has one binding for the same (member, role) pair. Ugly (two Terraform states own the same effective binding) but functionally safe during migration.

## Rationale for the interlock decision

The design constraint driving the interlock is: **obs-baseline must be usable before Tier 0 stack 40 ships**. When I designed obs-baseline v0.1.0, Tier 0 stack 40 was a placeholder README. Obs-baseline needed to work &mdash; log bucket + retention + exports &mdash; even without the org sink existing yet.

Options I considered for obs-baseline v0.1.0:

- Wait to ship obs-baseline until Tier 0 stack 40 lands (delays a whole Tier 1 by a whole Tier 0 release cycle).
- Have obs-baseline not touch the writer identity at all (log bucket exists but any org sink pointing at it must have its own external binding).
- Have obs-baseline conditionally create the binding, gated on operator-provided input (`var.org_sink_writer_identity`).

I chose option 3. The deferred-integration hook lets obs-baseline handle the binding during the transition period without knowing whether Tier 0 stack 40 exists.

Once Tier 0 stack 40 ships, the natural home for the binding is this stack (sink + IAM are one atomic unit). Migration is one variable flip on obs-baseline. Not zero-cost, but bounded.

## Trade-offs

- **Two-owner transitional period**: for the interval between Tier 0 v0.4.0 ship and the operator's next obs-baseline update, both stacks own the binding. Two Terraform states each report the binding as owned. `google_project_iam_member` idempotency prevents functional issues; the state ugliness is cosmetic.
- **Empty filter is a cost decision**: an org sink with `filter = ""` captures everything &mdash; every audit log, every application log, every LB request log. That has a real GCP bill. Documented in the tfvars example and the `10-log-exports` cost-control guidance in obs-baseline.
- **`_Default` bucket has fixed 30-day retention** unless upgraded. A deployment that routes to `_Default` and expects year-long retention is misconfigured. Operators must route to a custom bucket (from obs-baseline) for anything beyond `_Default`'s defaults.

## Alternatives considered

**A. Sink in `gcp-observability-baseline` (moved from Tier 0).**
Rejected in [ADR-0003](0003-org-sink-in-tier0-not-obs-baseline.md). Would force obs-baseline to hold `roles/logging.configWriter` at Org scope, violating least-privilege for a baseline that otherwise runs project-scoped.

**B. `filter = "severity>=WARNING"` default (cost-conservative).**
Rejected. Losing INFO-level logs is losing the timeline for most incident investigations. Cost is real but recoverable via exclusions and downstream tier retention; missing logs are not recoverable.

**C. `include_children = false` default (Org-scope logs only).**
Rejected. Near-zero use case &mdash; almost no logs are written at Org scope. Would leave the operator wondering why the destination bucket is empty.

**D. This stack does not create the IAM binding &mdash; obs-baseline is the sole owner.**
Rejected. Sink + writer identity are one atomic unit. If this stack creates the sink but not the IAM, the operator must apply obs-baseline before the sink can actually write &mdash; and if obs-baseline is not applied, the sink is broken. Coupling ownership avoids the broken-partial-apply state.

**E. `unique_writer_identity = false` (share the default logging SA across sinks).**
Rejected. Audit clarity requires each sink have its own writer identity so `principalEmail` uniquely identifies which sink wrote a log entry when it lands in the destination. Also: any per-sink IAM grant on the destination can be scoped to the specific writer SA.

## Controls this decision supports

Language convention: "supports controls typically found in ..." not "complies with". Precise clause IDs in [`../security/control-mapping.md`](../security/control-mapping.md).

- **NIS2** &mdash; incident detection and logging areas (Art. 21). Org-wide log aggregation is the foundation for cross-tenant detection.
- **ISO/IEC 27001 &amp; 27002** &mdash; logging and monitoring area, event logging control. Org-scope sink centralises collection.
- **NIST CSF** &mdash; DE (Detect) function, anomalies and events + continuous monitoring categories. PR (Protect) function, protective technology / audit capability.
- **NIST SP 800-53** &mdash; AU (Audit and Accountability) family, especially AU-2 (event logging), AU-12 (audit record generation), AU-4 (audit log storage capacity via retention on destination bucket).
- **CIS Google Cloud Foundation Benchmark** &mdash; logging section (aggregate sink at org level, filter and retention discipline).
- **Google Cloud Architecture Framework** &mdash; operational excellence pillar (centralised observability) + security pillar (audit trail).

## Maturity path

**Current implementation** &mdash; single org sink to `plogs`'s log bucket (default `_Default`, override to custom); `include_children = true`; empty filter; IAM binding owned here.

**Enhanced**:
- Multiple sinks (via `custom_sinks` addition to variables) so per-team / per-compliance-scope logs route to distinct destinations. Example: PCI-scoped audit logs to a dedicated PCI bucket with 10-year retention; general logs to standard bucket with 30-day.
- Sink-level exclusions catalog for known high-volume-low-value log names (LB probes, container liveness checks). Reduce cost without losing signal at the project level.
- Route directly to BigQuery for near-real-time analytics on the audit stream.
- **Least-privilege on the writer-identity IAM binding**: scope the current project-level `roles/logging.bucketWriter` grant to the specific destination log bucket &mdash; via IAM Conditions restricting `resource.name` to the bucket path, or via bucket-level IAM if / when GCP surfaces it. The current project-scope grant is functionally correct but grants the writer SA the ability to write to any log bucket in `plogs`, not just the one this sink targets. Bucket-scoped is the least-privilege posture.

**High-isolation option**:
- Dedicated org sinks per compliance regime (`sink_pci`, `sink_gdpr`, `sink_regulated`) each routing to isolated destination projects with distinct IAM. Downstream analytics never crosses compliance boundaries.
- Log encryption via CMEK on the destination log bucket (BYOK for the log data itself).
- Immutable retention (Log Bucket Object Lock equivalent) for audit logs to satisfy tamper-evidence requirements.

Full portfolio-level roadmap in [`../security/maturity.md`](../security/maturity.md).

## References

- [`../../stacks/40-org-logging/README.md`](../../stacks/40-org-logging/README.md) &mdash; stack documentation.
- [`../architecture.md`](../architecture.md) &mdash; section on `40-org-logging`.
- [ADR-0003](0003-org-sink-in-tier0-not-obs-baseline.md) &mdash; sibling decision: why the sink lives in Tier 0, not in obs-baseline.
- [ADR-0009](0009-layered-segmentation-hierarchy-first.md) &mdash; org sink is one of the mechanisms that makes Scale 1 governance visible (audit).
- Consumer: [`../../../../baseline-projects/gcp-observability-baseline/stacks/00-log-storage/README.md`](../../../../baseline-projects/gcp-observability-baseline/stacks/00-log-storage/README.md) &mdash; the deferred-integration hook that this stack supersedes.
- [GCP: Aggregated sinks](https://cloud.google.com/logging/docs/export/aggregated_sinks) &mdash; canonical reference for org-scope sinks + `include_children`.
- [GCP: Sink writer identity](https://cloud.google.com/logging/docs/api/tasks/exporting-logs#writer_identity) &mdash; canonical reference for `unique_writer_identity` and the IAM binding pattern.
