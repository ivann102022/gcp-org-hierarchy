<!--
File:        docs/adr/0013-break-glass-user-model.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0013: Break-glass model for org-scope IAM

**Status**: Accepted
**Date**: 2026-08-08
**Deciders**: Ismael Cruz
**Tags**: gcp, tier-0, iam, break-glass, incident-response

## Context

Org Admin (`roles/resourcemanager.organizationAdmin`) is the most privileged role in GCP. It grants the ability to modify every folder, project, org policy, and IAM binding across the entire Organization. It exists for a reason &mdash; catastrophic recovery (a bad `terraform apply` locking out the platform team, a compromised SA, a Workspace super-admin removal) requires someone with that authority to intervene.

Two failure modes appear in real deployments:

1. **Too many Org Admins.** Every platform engineer holds the role "just in case". First incident: an over-permissioned user makes a well-intentioned change that cascades. Second incident: audit finds 15 people with Org Admin and cannot narrow down blast radius.

2. **No Org Admin at all.** Terraform-only IAM management. First incident: Terraform SA gets locked out (its own binding removed by a previous apply). Second incident: nobody has the credential to recover.

Both are avoidable with an explicit break-glass model.

## Decision

Ship a **dedicated `break_glass_principals` variable** in stack `50-org-iam`, separate from `org_admins`, with these operational properties:

1. **Dedicated group**, not user emails. Typical value: `["group:break-glass@example.com"]`.
2. **Membership is empty by default.** The group exists in Cloud Identity / Workspace with zero members during normal operation.
3. **Membership is populated only during an active incident**, via a ticket / Slack / audit-trailed procedure. Grant the specific human whose account is on-call for the incident.
4. **Membership is removed after the incident closes.** Ideally within a defined SLA (hours, not days).
5. **Log-based alert fires on any action performed by a member of the break-glass group.** The alert lives in `gcp-observability-baseline/20-monitoring-and-budgets` (already scaffolded as `iam_policy_changes` and `service_account_key_created`; a dedicated `break_glass_activation` alert can be added), consuming `break_glass_principals` from this stack's output as the filter target.

The break-glass principal holds `roles/resourcemanager.organizationAdmin` &mdash; same role as `org_admins`. Separation is not about privilege; it is about **audit alerting granularity**. Alerts can target "break-glass" specifically without alerting on every action performed by an on-call platform engineer.

## Rationale

**Why a dedicated group with zero members?**

- **Zero-members baseline** means the alert is never noisy under normal operation. Every action attributed to a break-glass principal is a real incident signal.
- **Group indirection** decouples "who has Org Admin during an incident" from "who is on the platform team". On-call rotates; group membership follows.
- **Audit trail** for group membership changes lives in Workspace / Cloud Identity, orthogonal to GCP IAM. Two independent audit surfaces (who added the member; what the member did) are stronger than one.

**Why the same role as `org_admins` (not a stronger role)?**

There is no role stronger than Org Admin. The distinction is not about privilege &mdash; both `org_admins` and `break_glass_principals` hold the same effective authority. The distinction is that `break_glass_principals` is **flagged for alerting** while `org_admins` is not. Any action by an `org_admins` member is normal daily work; any action by a `break_glass_principals` member is an incident.

**Why not just tag the individual break-glass user in `org_admins`?**

- Requires the operator to remember which member of `org_admins` is the break-glass one when writing alert filters.
- Breaks when the break-glass user rotates.
- Loses the group-indirection audit surface (membership changes at group scope are the cleaner event).

## Trade-offs

- **Cloud Identity / Workspace admin is required for the model to work.** Terraform cannot manage group membership (except with Groups API, which is off by default and requires additional setup). The operator must have a documented, audited procedure for adding a member to the break-glass group when an incident starts.
- **The model relies on operational discipline** &mdash; if the group is populated "temporarily" and never emptied, the model collapses into "everyone has Org Admin". Mitigated by: (a) log-based alert on group membership changes; (b) documented SLA for removing members post-incident; (c) periodic audit that the group is empty during normal operation.
- **The alert must be actually watched.** A break-glass activation alert that lands in an unmonitored channel is worse than useless. Requires the observability pipeline (obs-baseline notification channels) to include an escalation path that is actively read.

## Alternatives considered

**A. All Org Admins in `org_admins`, no break-glass distinction.**
Rejected. Loses the alert-granularity property. Real incidents get lost in the noise of routine platform-team actions.

**B. Break-glass as an individual user email (`user:oncall@example.com`), not a group.**
Rejected. Ties break-glass to a specific human; rotation is friction; membership change is not audited independently.

**C. Break-glass with a stronger role than Org Admin.**
Not possible in GCP &mdash; Org Admin is the strongest role. Any attempt (e.g. creating a custom role at Org scope with all permissions) is functionally equivalent and less clearly audited.

**D. Break-glass via just-in-time IAM (e.g. Privileged Access Manager style).**
Deferred. GCP's IAM Recommender + IAM Conditions can implement JIT elevation patterns, but the tooling is not yet as mature as the Azure PIM equivalent. Would evaluate again in a future release when GCP's JIT story is more prescriptive.

**E. No break-glass model &mdash; rely on Google support for recovery.**
Rejected. Google support recovery is real (they can restore a Workspace super-admin) but takes hours to days. Break-glass gives the operator minutes-to-recovery for the majority of incidents.

## Controls this decision supports

Language convention: "supports controls typically found in ..." not "complies with". Precise clause IDs in [`../security/control-mapping.md`](../security/control-mapping.md).

- **NIS2** &mdash; incident handling and recovery areas (Art. 21). Break-glass is a documented recovery capability.
- **ISO/IEC 27001 &amp; 27002** &mdash; privileged access management, incident management areas. Break-glass model addresses both.
- **NIST CSF** &mdash; RS (Respond) function, particularly recovery planning. PR (Protect) function, particularly access control (privileged access management).
- **NIST SP 800-53** &mdash; AC-2 (account management, especially privileged accounts), AC-6 (least privilege), IR (Incident Response) family.
- **CIS Google Cloud Foundation Benchmark** &mdash; IAM best practices, particularly minimal use of primitive roles at high scope.
- **Google Cloud Architecture Framework** &mdash; security pillar (least privilege) + operational excellence pillar (incident preparedness).

## Maturity path

**Current implementation** &mdash; dedicated `break_glass_principals` variable, alert-friendly output, obs-baseline consuming the principals list for log-based alert filtering. Operational procedures (group membership, SLA for removal, incident ticketing) are documented but not enforced by Terraform.

**Enhanced**:
- Add IAM Conditions on the break-glass binding so it is only active during declared incident windows (via `request.time` conditions or Access Context Manager access levels).
- Add automated group membership expiration via Cloud Identity APIs (member auto-removed after N hours).
- Add a `break_glass_activated` custom metric + dashboard in obs-baseline so incidents are visible at a glance.
- Integrate with incident management system (ServiceNow / PagerDuty / Opsgenie) so break-glass activation opens an incident ticket automatically.

**High-isolation option**:
- Multi-party approval for break-glass activation (two humans required to add a member to the group).
- Cross-org sign-off for break-glass in regulated tenants (dedicated approver group in a separate GCP org / Workspace).
- Time-limited break-glass tokens via Workload Identity Federation with short TTL, replacing group membership.

Full portfolio-level roadmap in [`../security/maturity.md`](../security/maturity.md).

## References

- [`../../stacks/50-org-iam/README.md`](../../stacks/50-org-iam/README.md) &mdash; stack documentation.
- [`../architecture.md`](../architecture.md) &mdash; section on `50-org-iam`.
- Consumer: [`../../../../baseline-projects/gcp-observability-baseline/stacks/20-monitoring-and-budgets/README.md`](../../../../baseline-projects/gcp-observability-baseline/stacks/20-monitoring-and-budgets/README.md) &mdash; alert catalog consumes the `break_glass_principals` output as filter target.
- [GCP: Privileged access management](https://cloud.google.com/architecture/framework/security/privileged-access) &mdash; canonical reference for the pattern.
