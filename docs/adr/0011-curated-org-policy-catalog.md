<!--
File:        docs/adr/0011-curated-org-policy-catalog.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0011: Curated org-policy catalog with dry-run-first default

**Status**: Accepted
**Date**: 2026-08-08
**Deciders**: Ismael Cruz
**Tags**: gcp, tier-0, org-policies, dry-run, security-baseline

## Context

`google_org_policy_policy` at Organization scope is the most powerful preventative control in a GCP foundation &mdash; a single well-placed constraint can eliminate an entire class of misconfiguration across every current and future project in the org.

It is also the fastest way to break a live workload. `constraints/compute.vmExternalIpAccess = deny all` applied without warning removes every existing external IP allocation at next VM reconciliation. `constraints/iam.disableServiceAccountKeyCreation = enforce` breaks every pipeline that still uses SA keys. The blast radius of enforce-first is the whole org.

There are hundreds of Google-managed constraints available. The stack could just expose the raw resource and let the operator pick. That would fail two operator populations:

1. The operator who does not know which constraints matter and copies the first 20 they find on a blog.
2. The operator who applies `enforce = true` on day 1 because that is the only value they see in the examples.

I designed stack `30-org-policies` around two convictions from real projects:

- **A curated catalog matters more than exposing every constraint.** The 20% of constraints that block 80% of the risk are the ones worth shipping with opinion. The long tail belongs in `custom_org_policies`.
- **Dry-run first, enforce later, per policy, by decision.** Every policy exists in dry-run mode by default; the operator flips individual policies to enforce after validating them.

## Decision

Ship a **curated catalog of 8 org policies** in stack `30-org-policies`. Each policy has:

- Its own `enable_<policy>` switch (default `false` &mdash; opt-in).
- A default `dry_run = true` (audit-only) via `var.default_dry_run`.
- Per-policy override to promote to enforce via `var.enforce_overrides`.

Additional policies land in `var.custom_org_policies`; the catalog is not the only way.

### The catalog

| Catalog key | Constraint | What I have learned about applying it |
|---|---|---|
| `disable_sa_keys` | `iam.disableServiceAccountKeyCreation` | High signal, low false-positive when WIF is set up. Almost every prior incident I have investigated involved a leaked SA key. Safe to enforce day 1 if the WIF story is ready. |
| `require_oslogin` | `compute.requireOsLogin` | Kills project-wide SSH keys and forces SSH-via-IAM. Safe to enforce but needs a real-user test first (OS Login IAM roles must be set up for humans who SSH to VMs). |
| `deny_external_ip` | `compute.vmExternalIpAccess` (deny all) | Powerful but breaks NAT-less setups. Only enforce after Cloud NAT is confirmed for every VPC / subnet workload can reach the internet. |
| `prevent_public_storage` | `storage.publicAccessPrevention` | Safe to enforce day 1. The number of "public GCS bucket" incidents in the industry justifies this being the first policy every org enforces. |
| `restrict_sql_public_ip` | `sql.restrictPublicIp` | Cloud SQL best practice is private-IP anyway. Safe to enforce day 1 unless there is legacy public-IP SQL. |
| `allowed_policy_member_domains` | `iam.allowedPolicyMemberDomains` | Blocks IAM leaks to external tenants. Very effective. Requires the operator to know their Workspace `customer_id` (via `gcloud organizations list`). |
| `trusted_image_projects` | `compute.trustedImageProjects` | Enforces VM image supply chain. Requires the operator to have catalogued which image projects are legitimate (typically `debian-cloud`, `ubuntu-os-cloud`, `cos-cloud`, plus custom golden-image projects). |
| `resource_locations` | `gcp.resourceLocations` | Region pinning for data residency. Default `in:eu-locations` reflects the customer profiles I have worked with; override for US-only or specific-region deployments. |

These 8 are the constraints I have consistently deployed across engagements. Others (VPC-SC, org-scope SCC, Assured Workloads) belong in dedicated stacks (data-plane / compliance) rather than the general-purpose catalog.

### Dry-run-first workflow

Recommended promotion order (from safest to enforce first to most operationally risky):

1. `prevent_public_storage` &mdash; enforce day 1.
2. `disable_sa_keys` &mdash; enforce day 1 (if WIF is in place).
3. `restrict_sql_public_ip` &mdash; enforce day 1.
4. `require_oslogin` &mdash; enforce after real-user SSH test.
5. `deny_external_ip` &mdash; enforce after Cloud NAT verified across all VPCs.
6. `resource_locations` &mdash; enforce after audit confirms workloads honour target regions.
7. `allowed_policy_member_domains` &mdash; enforce after `allowed_customer_ids` list validated.
8. `trusted_image_projects` &mdash; enforce after image project allow-list catalogued.

Operators promote via `enforce_overrides = { <policy_key> = true }`. Reversal is one line back.

## Rationale

### Why curated over "expose everything"

A raw wrapper over `google_org_policy_policy` is one hundred lines of Terraform. It provides zero value beyond letting the operator type the constraint ID themselves. The value is in the opinion: **these 8 constraints, in this order, tested against workloads that resemble the target customer profile**. That opinion is what makes this a portfolio artifact rather than a Google docs page transcription.

### Why dry-run default

Every enforcement incident I have investigated started the same way: an operator flipped a policy to enforce without understanding the workload landscape. Dry-run mode gives the same audit signal (violations show up in `protoPayload.metadata.dryRunResults`) without the operational risk. **Dry-run is not the wrong default &mdash; it is the correct default when the operator has not yet validated impact.**

The operator who wants "enforce immediately org-wide" for all 8 policies can set `default_dry_run = false` in one line. But they will make that choice consciously, having read this ADR and the tfvars example ordering guidance.

### Why per-policy enable (all default false) rather than "enable everything, opt-out per policy"

Two reasons:

1. **Fresh apply is a no-op.** Enable-everything-by-default means `terraform apply` on first checkout provisions 8 org policies. That is a lot of state for what should be an intentional decision.
2. **The catalog will grow.** When I add a 9th policy in a future release, `enable-everything` would silently enable it on next apply. `enable-per-policy` requires an explicit opt-in.

## Trade-offs

- **Two knobs to flip per policy** (`enable_X = true` and `enforce_overrides = { X = true }`). Slight ergonomic cost. Mitigated by the two knobs being at different levels &mdash; the `enable` is a stack-level decision ("is this policy in scope for this org?"), the `enforce` is a lifecycle decision ("has this policy been validated?"). They deserve separate switches.
- **`default_dry_run = true` gives operators a false sense of security.** A policy in dry-run does nothing preventative &mdash; it only surfaces violations. If nobody watches the audit log, dry-run is worthless. Mitigated by (a) obs-baseline's alert catalog including a policy-violation alert; (b) tfvars example calling out the promotion workflow explicitly.
- **8 policies is a subset.** GCP has dozens of constraints; the portfolio covers eight. Operators wanting more use `custom_org_policies`, which is a raw wrapper without the catalog's opinion.

## Alternatives considered

**A. Raw wrapper &mdash; expose `google_org_policy_policy` without a catalog.**
Rejected. Zero value-add; the whole point of the stack is to embody opinion about which constraints matter.

**B. Enable-everything default with opt-out.**
Rejected. Silent enablement of future catalog additions on future applies. Deploy-time surprises are unacceptable for a policy stack.

**C. `default_dry_run = false` (enforce-first).**
Rejected. Every enforcement incident I have investigated started with enforce-first. Not shipping that footgun as the default is the whole point of dry-run-first.

**D. Split the catalog into "safe to enforce day 1" vs "needs validation" as separate stacks.**
Rejected. The safety of a policy depends on the customer's workload state, not on an inherent property of the policy. `prevent_public_storage` is safe day 1 for 95% of customers and breaks the 5% with legacy public buckets. The split-into-stacks pattern misleadingly implies "safe" is a property of the constraint, when it is a property of the deployment. The per-policy promotion workflow is the correct granularity.

**E. Ship a "curated ENFORCE" bundle for customers who explicitly want opinionated enforcement.**
Deferred to a future minor version. Would look like a variable `enable_curated_enforce_bundle = true` that enables the 4-5 policies I consider safe to enforce day 1 in every deployment, all at enforce. Not in v0.1.0 of the stack &mdash; get customer feedback on the catalog first.

## Controls this decision supports

Language convention: "supports controls typically found in ..." not "complies with". Precise clause IDs in [`../security/control-mapping.md`](../security/control-mapping.md).

- **NIS2** &mdash; risk management measures area (Art. 21). Preventative controls at Org scope are the strongest expression of a policy-based risk approach.
- **ISO/IEC 27001 &amp; 27002** &mdash; access control, cryptography, system acquisition areas. Constraints like `disable_sa_keys` and `require_oslogin` directly support policy-based access controls.
- **NIST CSF** &mdash; PR (Protect) function, information protection processes and procedures category.
- **NIST SP 800-53** &mdash; CM (Configuration Management) family, particularly CM-6 (configuration settings) and CM-7 (least functionality).
- **CIS Google Cloud Foundation Benchmark** &mdash; direct alignment. Every catalog policy corresponds to a specific CIS recommendation.
- **Google Cloud Architecture Framework** &mdash; security pillar, particularly the "hardening at the platform layer" pattern.

## Maturity path

**Current implementation** &mdash; 8-policy catalog, dry-run default, per-policy enable + enforce overrides.

**Enhanced**:
- Add `google_org_policy_custom_constraint` for organization-specific constraints (e.g. "deny GKE clusters without private endpoints for regulated environments").
- Add IAM Conditions on the org policies themselves (e.g. "this constraint applies except in `sandbox` folder").
- Add Policy Controller / Config Sync gating so a policy PR must pass automated impact analysis before apply.
- Add a bundled "safe-to-enforce day 1" mode (see Alternative E) once the catalog stabilises.

**High-isolation option**:
- Add VPC Service Controls perimeters as org-scope constraints for regulated projects.
- Add Access Context Manager access levels referenced by org-policy conditions (e.g. "external-IP allowed only when caller passes access level X").
- Add Assured Workloads binding constraints for FedRAMP / IL / EU sovereign requirements.
- Per-folder overrides with stricter enforcement in `LandingZones/HostPrj/PRO` vs looser in `Sandbox`.

Full portfolio-level roadmap in [`../security/maturity.md`](../security/maturity.md).

## References

- [`../../stacks/30-org-policies/README.md`](../../stacks/30-org-policies/README.md) &mdash; stack documentation.
- [`../architecture.md`](../architecture.md) &mdash; section on `30-org-policies`.
- [ADR-0009](0009-layered-segmentation-hierarchy-first.md) &mdash; org policies are the enforcement mechanism for Scale 1 governance decisions.
- [ADR-0006](0006-landing-zones-hostprj-serviceprj-env-split.md) &mdash; the folder shape that lets org policies attach at HostPrj vs ServicePrj scope for the differentiated guardrail pattern.
- [GCP Organization Policy overview](https://cloud.google.com/resource-manager/docs/organization-policy/overview) &mdash; canonical reference.
- [CIS Google Cloud Foundation Benchmark](https://www.cisecurity.org/benchmark/google_cloud_computing_platform) &mdash; source for many of the catalog choices.
