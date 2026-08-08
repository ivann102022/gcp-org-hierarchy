<!--
File:        docs/security/maturity.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Maturity roadmap for the architectural decisions in this repo.
             For each decision: current implementation (what I built), enhanced
             (natural evolution for stronger requirements), high-isolation
             option (what I would build for regulated / sovereign / high-trust
             scenarios). The point is to show the current design as one point
             on a spectrum, not as the only possible answer.
-->

# Maturity roadmap

## Purpose

Every decision in this repo represents **one point on a spectrum**. This document maps that point in three dimensions:

1. **Current implementation** &mdash; what I built and shipped, matching the requirements of the customer engagements the portfolio is anonymised from.
2. **Enhanced** &mdash; the natural evolution when the current design meets stricter requirements without changing the fundamental architecture. Additive controls; same shape.
3. **High-isolation option** &mdash; what I would build if the customer had regulated / sovereign / high-trust requirements that the current design cannot meet.

The point is not to say "the current design is incomplete" &mdash; it isn't; it meets the requirements it was built for. The point is to show that I know the spectrum and can position a customer at the right point on it.

## Portfolio-level maturity signal

A reviewer looking at this repo can read the maturity path in three ways:

- **"This is what he did"** &mdash; the current implementation column shows the concrete design I have delivered.
- **"Here's how he thinks it evolves"** &mdash; the enhanced column shows the natural next steps under increased scrutiny.
- **"Here's how he handles hard cases"** &mdash; the high-isolation column shows the design for scenarios where the current design is insufficient.

Missing any of these three would leave a gap: only column 1 reads as "he built one thing"; only column 3 reads as "he only knows extreme cases"; only column 2 reads as "he theorises about evolution without a starting point". All three together read as **judgment across the spectrum**.

## Per-decision maturity

### Layered segmentation ([ADR-0009](../adr/0009-layered-segmentation-hierarchy-first.md))

| Dimension | Detail |
|---|---|
| **Current** | Three scales: Resource Hierarchy (Scale 1) + VPC (Scale 2) + distributed firewall (Scale 3). Sufficient for standard enterprise workloads. |
| **Enhanced** | Add hierarchical firewall policies at folder scope. Add tag-based firewall rules using Resource Manager tags. Add Policy Controller / Config Sync gating on every apply. |
| **High-isolation** | Introduce Scale 4 (data-plane segmentation): VPC Service Controls perimeters around sensitive projects; Private Service Connect for all internal service consumption; Access Context Manager access levels; Assured Workloads for regulated tenants. |

### 1:1 folder per platform project ([ADR-0005](../adr/0005-folder-per-platform-project.md))

| Dimension | Detail |
|---|---|
| **Current** | 5 sub-folders under `Platform` (Logs / Management / IAM / DNS / Ingress), one platform project each. `sandbox` under `Sandbox` root. |
| **Enhanced** | Per-project org-policy attach points beyond folder defaults. Hierarchical firewall policies at `Ingress` folder scope. Tag-based IAM Conditions on folder bindings. |
| **High-isolation** | Split a platform concern into two folders when compliance demands it (e.g. `Logs` &rarr; `LogsRegulated` + `LogsGeneral`). Wrap `IAM` and `Management` folders in VPC Service Controls perimeters. Assured Workloads for the regulated sub-tree. |

### HostPrj / ServicePrj + PRO/PRE/DEV split ([ADR-0006](../adr/0006-landing-zones-hostprj-serviceprj-env-split.md))

| Dimension | Detail |
|---|---|
| **Current** | Role-first with `HUB` flat, `HostPrj` / `ServicePrj` env-split PRO/PRE/DEV. Team-based separation (Network+Security vs Systems+Applications). |
| **Enhanced** | Per-BU sub-folders under each env grandchild (e.g. `HostPrj/PRO/BU-A`). Hierarchical firewall policies at `HostPrj` and `ServicePrj` folder scope. IAM Conditions on folder bindings. |
| **High-isolation** | Parallel `LandingZones/Regulated/<env>` sub-tree with independent HUB, HostPrj, ServicePrj, stricter policy attach points. Access Context Manager access levels on the regulated sub-tree. Assured Workloads for regulated projects. |

### Public ingress bypasses perimeter ([ADR-0008](../adr/0008-ingress-bypasses-perimeter-appliance.md))

| Dimension | Detail |
|---|---|
| **Current** | Public ingress via Global LB + Cloud Armor + WAF in `pingress`; backends via Private Service Connect / internal LB. Perimeter FortiGate for egress + east-west + VPN only. |
| **Enhanced** | Add IAP for admin ingress paths (bypassing VPN + FortiGate for management). reCAPTCHA Enterprise on Cloud Armor. Cloud Armor adaptive protection. Cloud CDN in front of Global LBs. |
| **High-isolation** | Separate `pingress` by exposure tier (`pingress-internet`, `pingress-partner`, `pingress-admin`) with independent Cloud Armor policies, TLS certs, audit trails. |
| **BeyondCorp option** | Move admin ingress fully to IAP + BeyondCorp Access Context Manager. Remove VPN termination for admin users (workload-to-workload VPN remains for on-prem integration). |

### Single shared perimeter HUB ([ADR-0010](../adr/0010-single-shared-perimeter-hub.md))

| Dimension | Detail |
|---|---|
| **Current** | Single HUB project with single FortiGate HA cluster shared across PRO / PRE / DEV. Cost-effective; relies on Scale 3 distributed firewall for microsegmentation. |
| **Enhanced** | Hierarchical firewall policies at folder scope so PRO gets stricter rules than DEV even through the same appliance. Per-env IAM Conditions on the HUB project. Per-env log labels + dashboards + alert channels. |
| **High-isolation** | HUB-per-environment (`HUB-PRO`, `HUB-PRE`, `HUB-DEV`) with independent FortiGate HA clusters. 3&#x00D7; cost accepted for full environmental isolation. Warranted for: PCI CDE, sovereign-cloud requirements, multi-tenant SaaS with different customer trust domains per env. |
| **Dedicated CDE / regulated overlay** | Fourth HUB (`HUB-REGULATED`) alongside the shared HUB, dedicated to CDE or regulated-workload traffic. Distinct cluster, rules, and audit trail scoped to the compliance obligation. |

### Curated org-policy catalog ([ADR-0011](../adr/0011-curated-org-policy-catalog.md))

| Dimension | Detail |
|---|---|
| **Current** | 8-policy catalog (disable_sa_keys, require_oslogin, deny_external_ip, prevent_public_storage, restrict_sql_public_ip, allowed_policy_member_domains, trusted_image_projects, resource_locations) with per-policy enable switches and dry-run default. `custom_org_policies` for additions. |
| **Enhanced** | Custom constraints via `google_org_policy_custom_constraint`. IAM Conditions on policies (e.g. "except in sandbox folder"). Policy Controller / Config Sync gating on PRs. Bundled "safe-to-enforce day 1" mode. |
| **High-isolation** | VPC Service Controls perimeters as org-scope constraints for regulated projects. Access Context Manager access levels referenced by org-policy conditions. Assured Workloads binding constraints for FedRAMP / IL / EU sovereign. Per-folder policy overrides (stricter in PRO, looser in Sandbox). |

### Org sink design ([ADR-0012](../adr/0012-org-sink-design.md))

| Dimension | Detail |
|---|---|
| **Current** | Single org sink to `plogs` log bucket (default `_Default`, override to custom); `include_children = true`; empty filter; IAM binding owned by Tier 0 stack 40. |
| **Enhanced** | Multiple sinks via `custom_sinks` for per-team / per-compliance-scope routing (e.g. PCI logs to dedicated bucket with 10-year retention). Sink-level exclusions catalog for high-volume noise. Direct BigQuery routing for near-real-time analytics. |
| **High-isolation** | Dedicated org sinks per compliance regime (`sink_pci`, `sink_gdpr`, `sink_regulated`) each routing to isolated destination projects. CMEK on destination log buckets. Immutable retention (Object Lock equivalent) for tamper-evidence. |

### Break-glass user model ([ADR-0013](../adr/0013-break-glass-user-model.md))

| Dimension | Detail |
|---|---|
| **Current** | Dedicated `break_glass_principals` variable (typically a group with empty membership). Log-based alert in obs-baseline consumes the principals list. Operational procedures for membership rotation documented but not enforced. |
| **Enhanced** | IAM Conditions on break-glass binding (active only during declared incident windows via `request.time` or Access Context Manager access levels). Automated group membership expiration via Cloud Identity APIs. `break_glass_activated` custom metric + dashboard. Integration with incident management system for auto-ticketing. |
| **High-isolation** | Multi-party approval for break-glass activation (two humans required). Cross-org sign-off for regulated tenants. Time-limited break-glass tokens via WIF with short TTL, replacing group membership. |

### Tag catalog + opt-in ([ADR-0014](../adr/0014-tag-catalog-choice.md))

| Dimension | Detail |
|---|---|
| **Current** | 4-key reference catalog opt-in (environment, data-classification, cost-center opt-in, owner opt-in). `custom_tag_keys` for extensions. `purpose = "GCE_FIREWALL"` for max compatibility. |
| **Enhanced** | Automated tag binding via Cloud Run / Cloud Function trigger on project creation. Tag-based IAM Condition examples in `custom_org_iam_bindings`. Tag-based org policy conditions in `30-org-policies`. BigQuery integration for tag-based cost attribution rollup. |
| **High-isolation** | `compliance-scope` tag key with values `pci`/`hipaa`/`gdpr-strict`/`sovereign`/`none` bound on every project, triggering stricter policies via IAM Conditions. `criticality` tag for regulated tier-1 workloads with dedicated on-call / backup / DR alignment. Assured Workloads binding for regulated tenants. |

### Per-stack Terraform deployment identities (portfolio-wide)

Not tied to a specific ADR &mdash; a portfolio-wide maturity dimension surfaced during the section-50 review.

| Dimension | Detail |
|---|---|
| **Current** | A small number of Terraform service accounts hold broad roles at Org scope (Project Creator, Org Policy Admin, Logging Admin). One SA may run multiple stacks. Sufficient for bootstrap and for portfolio-scale deployments. |
| **Enhanced** | One dedicated Terraform SA per Tier-0 stack (`sa-tf-00-org-baseline`, `sa-tf-10-folders`, `sa-tf-20-projects`, `sa-tf-30-org-policies`, `sa-tf-40-org-logging`, `sa-tf-50-org-iam`, `sa-tf-60-tags`). Each SA holds only the roles its stack needs at the scope its stack acts on. Blast radius of a compromised CI credential is bounded to that stack's resources. |
| **High-isolation** | Per-stack SAs plus PAM/JIT elevation for the Terraform apply operation itself: the SA holds no permissions at rest; a scheduled or on-demand entitlement grants it the required roles for the duration of an apply, then removes them. Combined with audit alerting on each entitlement grant, this reduces the "compromised CI = compromised Org" scenario to a much narrower window. |

Retiring the default broad grants GCP applies on Organization creation (`domain:<org>.com` &rarr; `roles/resourcemanager.projectCreator` / `roles/billing.creator`) is the first concrete step in this direction and is part of the steady-state framing in [`50-org-iam` README](../../stacks/50-org-iam/README.md).

### Access authorization guardrails via IAM Deny (portfolio-wide)

Complementary to allow-based IAM. Not currently in the portfolio; documented here as a maturity direction.

| Dimension | Detail |
|---|---|
| **Current** | Only allow-based bindings (`google_organization_iam_member` and equivalents). Access = union of granted roles minus what constraints (org policies) prevent as configurations. |
| **Enhanced** | Add `google_iam_deny_policy` at Org or Folder scope for specific critical permissions (`iam.serviceAccountKeys.create`, `resourcemanager.projects.delete`, `logging.sinks.delete`, `billing.accounts.close`). Deny policies override allow policies (subject to constraint semantics), giving hard "no matter what role you have, you cannot do X" guardrails. Complements `30-org-policies` (which prevents *configurations*) with prevention of *actions*. |
| **High-isolation** | Deny catalog per compliance regime (PCI / GDPR / regulated) attached at the relevant folder branches; IAM Conditions on deny exceptions require named principal + time window + justification. |

This is what 30 (Prevent-configuration) + 40 (Detect-action) + 50 (Authorize-principal) can become together at higher maturity: 30 blocks configurations, 40 sees what happens, 50 authorizes *what a principal can even attempt*, and IAM Deny closes the loop by *hard-blocking specific attempts*.

### Anchor + baseline for stack `00-org-baseline` ([ADR-0007](../adr/0007-content-rule-for-org-baseline.md))

| Dimension | Detail |
|---|---|
| **Current** | Data-source anchor + essential contacts. Content rule (org-scope + fundacional + not-a-discipline) prevents catch-all creep. |
| **Enhanced** | Add Cloud Asset Inventory feed configuration at org scope (if not routed via `40-org-logging`). Add org-level metadata / labels if GCP surface expands. |
| **High-isolation** | The content rule protects against absorption of discipline-specific concerns; no additional isolation controls apply at this layer. |

## Cross-decision maturity story

If I roll these individual maturity paths up into a portfolio-level statement:

**Current portfolio position** &mdash; enterprise-standard GCP foundation for customers running non-regulated workloads. Three-scale segmentation gives defense-in-depth; single perimeter HUB with distributed firewall balances cost and control; deliberate exclusion of ingress from the perimeter path uses Google's edge efficiently.

**Enhanced portfolio position** &mdash; add hierarchical firewall policies, tag-based governance, Policy Controller, IAP for admin flows. Same fundamental architecture, stricter enforcement. Typically warranted for financial services (non-CDE), healthcare (non-HIPAA-scoped), critical infrastructure operators under NIS2.

**High-isolation portfolio position** &mdash; HUB-per-env, regulated-workload sub-tree, VPC Service Controls perimeters, Assured Workloads, BeyondCorp for admin access, Access Context Manager everywhere. Warranted for PCI CDE, sovereign-cloud, multi-tenant SaaS with different customer trust domains, or GxP-validated systems.

Each level is a natural evolution of the previous &mdash; not a rebuild. That progression is itself the portfolio's message: **I know the spectrum and can move customers along it as requirements change**.
