<!--
File:        docs/adr/0006-landing-zones-hostprj-serviceprj-env-split.md
Author:      Ismael Cruz
Version:     0.2.0
-->

# ADR-0006: `LandingZones` sub-tree &mdash; `HUB` flat + `HostPrj` / `ServicePrj` with environment sub-folders

**Status**: Accepted
**Date**: 2026-08-07 (updated 2026-08-08 with three-reasons rationale + maturity path)
**Deciders**: Ismael Cruz
**Tags**: gcp, tier-0, folders, landing-zones, shared-vpc, environments, segregation-of-duties

## Context

The `LandingZones` root folder is where Tier 2 LZs place their tenant projects. In my landing zone designs I have consistently faced three concurrent design questions:

1. **How does the LZ split into projects?** GCP's Shared VPC pattern has two roles: **host projects** hold the VPCs (network policy, subnets, peerings); **service projects** attach to a host to consume its VPCs. This is the pattern I use in both shipped GCP LZs (`gcp-lz-fortinet-multiproject`, `gcp-lz-ncc-bgp-appliance`).

2. **Do I split by environment?** Yes &mdash; every enterprise deployment I have delivered separates `PRO` / `PRE` / `DEV` at the project level (per-env IAM, per-env budgets, per-env change windows, per-env policy strength). Both shipped LZs already do this (`pnet-pro`, `pnet-pre`, `pnet-dev`).

3. **What about the HUB?** The hub network (perimeter appliance + Internet egress + VPN termination) is shared across environments in my designs &mdash; the economics and architectural reasoning are in [ADR-0010](0010-single-shared-perimeter-hub.md).

Combining (1) and (2) yields a 2&#x00D7;3 = 6-cell grid: {Host, Service} &#x00D7; {PRO, PRE, DEV}. Adding (3) yields 7 leaves under `LandingZones`.

How to shape the folder tree above those leaves drives IAM inheritance, policy attach points, and change velocity per subtree.

## Decision

**Role-first sub-tree** under `LandingZones`:

```
LandingZones
├── HUB                            [flat]         → pnet-hub (LZ-owned)
├── HostPrj                        [env-split]
│   ├── PRO                        → pnet-pro (LZ-owned)
│   ├── PRE                        → pnet-pre (LZ-owned)
│   └── DEV                        → pnet-dev (LZ-owned)
└── ServicePrj                     [env-split]
    ├── PRO                        → srv-pro (LZ-owned)
    ├── PRE                        → srv-pre (LZ-owned)
    └── DEV                        → srv-dev (LZ-owned)
```

Implementation: `var.reference_landing_zone_children` on `10-folders` maps each second-level folder to `{ has_environments = bool }`; entries with `has_environments = true` fan out to the env sub-folders declared in `var.reference_landing_zone_environments` (`["PRO", "PRE", "DEV"]` by default).

## Rationale (three converging reasons)

The HostPrj / ServicePrj split has three simultaneous reasons in my designs. Any one of them alone would be sufficient; the three together make the split load-bearing to the whole architecture.

### Reason 1 &mdash; Different ownership

In every enterprise I have worked with, **the humans who operate host projects are not the humans who operate service projects**:

- **HostPrj is operated by Network + Security teams** &mdash; they own the Shared VPC, the subnets, the peerings, the DNS integration, the network guardrails, the firewall policy skeleton.
- **ServicePrj is operated by Systems / Applications teams** &mdash; they own the compute (GKE, Cloud Run, GCE), the databases, the application services, the workload lifecycle.

The split into two folders is what makes IAM inheritance align cleanly with this team structure. `roles/compute.networkAdmin` at the `HostPrj` folder grants across all environments to the network team; `roles/container.developer` at the `ServicePrj` folder grants across all environments to the systems team. Neither team accidentally reaches into the other's domain.

Without the split, granting per-team access requires per-project IAM &mdash; error-prone and un-auditable at scale.

### Reason 2 &mdash; Different policy inheritance

Because the two folders exist, `30-org-policies` (planned) can attach **different constraint sets to each branch**:

- **HostPrj folder** &rarr; **network guardrails**: `compute.restrictSharedVpcSubnetworks`, `compute.restrictVpcPeering`, `compute.vmExternalIpAccess = deny all`, firewall enforcement, DNS logging enforcement.
- **ServicePrj folder** &rarr; **workload guardrails**: `compute.trustedImageProjects` allow-list, `compute.requireOsLogin`, `iam.disableServiceAccountKeyCreation`, container image provenance.

Without the split, all constraints attach at `LandingZones` and apply uniformly &mdash; forcing exceptions for host vs service concerns, which is exactly the pattern that erodes policy discipline over time.

This is a concrete instance of the general principle in [ADR-0009](0009-layered-segmentation-hierarchy-first.md): **Tier 0 folder shape causes what Tier N policy can express**. Getting `10-folders` right today is what lets `30-org-policies` express the right controls tomorrow.

**GCP-specific reinforcement &mdash; Shared VPC + Hierarchical Firewall Policies inheritance**. In Shared VPC, a VM interface belongs to a Service Project but attaches to a VPC that lives in the Host Project. Google evaluates the Hierarchical Firewall Policies (HFPs) that govern that interface using the **Host Project's** folder hierarchy, not the Service Project's. Consequence: an HFP attached at `LandingZones/HostPrj` propagates to every VM interface using any of the host VPCs &mdash; PRO, PRE, DEV &mdash; regardless of which Service Project owns the VM. Attaching an HFP at `LandingZones/ServicePrj` would NOT affect VMs whose interface is in a Host Project's Shared VPC (which is most workloads in this architecture). This is a Google-native technical justification for keeping the HostPrj branch as the primary network-policy attach point &mdash; not just an organisational convenience; it's where GCP evaluates network firewall inheritance for the Shared VPC pattern.

### Reason 3 &mdash; Different lifecycle

- **HostPrj** changes rarely &mdash; a new peering, a new subnet, a Shared VPC service attachment. Coordinated network change windows.
- **ServicePrj** changes constantly &mdash; workload deploys, cluster scaling, application version bumps. Application team cadence.

Bundling them into a single folder means change reviews mix "network peering added" with "app v3.2.1 deployed" &mdash; either the reviews are too heavy for the frequent changes or too light for the rare ones. Splitting lets each folder have its own change model.

## The ownership-first vs environment-first choice

The tree I chose puts **function/ownership at level 2** (HostPrj / ServicePrj) and **environment at level 3** (PRO / PRE / DEV). The alternative &mdash; environment at level 2, function at level 3 &mdash; is technically equivalent in resource count but semantically very different in what it optimises for.

The question underneath is: **what is the first frontier of governance under `LandingZones`?**

- **My answer**: function/ownership. Under `LandingZones`, the primary IAM delegation is *who operates this class of project* (Network+Security vs Systems+Applications). Once that boundary is drawn, environment is a within-team specialisation. `roles/compute.networkAdmin` at `HostPrj` folder scope grants across all envs to the Network team &mdash; who is exactly the person who should have it across all envs, because the network team owns Host Projects everywhere. The env split under `HostPrj` then lets the same team apply stricter policies to `PRO` than to `DEV`.
- **Env-first would answer**: environment. `LandingZones/PRO/{HostPrj, ServicePrj}` groups everything production first. Suits an org where PRO / PRE / DEV boundaries are the primary access-control axis (e.g. compliance-scoped PRO with different auditors from PRE/DEV) and where the network vs systems team split is secondary.

I chose function/ownership first because it matches the operational reality of the customers I have delivered for: the network team owns the host projects across environments; the systems team owns the service projects across environments; environment is a policy-strength gradient inside each ownership domain, not a team boundary.

**This choice is intentional and specific to my target customer profile.** For a customer whose compliance regime forces PRO to have a distinct operational team from PRE/DEV (regulated tier-1 workloads with separate change-window rules, separate on-call), env-first would be the correct call. See Alternative B below for the concrete rejection.

## Composite keys for grandchildren

`PRO` (and `PRE`, `DEV`) appears under both `HostPrj` and `ServicePrj`. GCP allows this because display-name uniqueness is enforced **per parent**, not globally. But Terraform's flat map (`for_each` over `local.all_folders`) needs unique keys.

Convention: **grandchildren under `LandingZones` use composite keys `<parent>-<env>`** in Terraform. The `display_name` in GCP stays the short form (`PRO` / `PRE` / `DEV`).

| Terraform key | GCP display_name | Parent |
|---|---|---|
| `HostPrj-PRO` | `PRO` | `HostPrj` |
| `HostPrj-PRE` | `PRE` | `HostPrj` |
| `HostPrj-DEV` | `DEV` | `HostPrj` |
| `ServicePrj-PRO` | `PRO` | `ServicePrj` |
| `ServicePrj-PRE` | `PRE` | `ServicePrj` |
| `ServicePrj-DEV` | `DEV` | `ServicePrj` |

Downstream consumers look up `folder_ids["HostPrj-PRO"]`, not `folder_ids["PRO"]`.

## Trade-offs

- **Terraform key vs display name distinction is a small extra concept for the reader**. Documented explicitly in the `10-folders` README and this ADR. If the reader forgets and uses `folder_ids["PRO"]`, they get `null` &mdash; fails fast at plan time. I accept the ergonomic cost to preserve the mechanical simplicity of a flat map.
- **Env customisation is per-env-list, not per-role**. If a customer wants `HostPrj` to have `PRO/PRE/DEV` but `ServicePrj` to have only `PRO/DEV`, they must either override `reference_landing_zone_environments` (which applies to both) or use `custom_folders`. Not painful in practice, but worth noting.
- **HUB as a folder-with-one-project feels wasteful**. Feels wasteful compared to putting `pnet-hub` directly under `LandingZones`. I keep the folder because it gives HUB the same IAM/policy attach point as HostPrj/ServicePrj &mdash; consistent treatment across the three roles is worth the one-line folder cost.

## Alternatives considered

**A. Flat &mdash; all 7 leaves directly under `LandingZones`.**
Rejected. Loses env-scope IAM inheritance. Per-env grants would need per-project bindings, defeating the folder inheritance benefit and breaking Reason 1 above (per-team access at scale). I have never delivered this in practice for LZs beyond single-tenant demos.

**B. Env-first &mdash; `LandingZones/PRO/{HostPrj, ServicePrj}`, `LandingZones/PRE/...`, `LandingZones/HUB`.**
Rejected for my target customer profile (see "The ownership-first vs environment-first choice" above). Legitimate alternative for customers where environment boundaries are the primary access-control axis (regulated tier-1 with separate PRO team from PRE/DEV, distinct compliance auditors per env). Technical reasons it also does not fit here: HUB sits at the same level as env roots but is not an env (structural mismatch); and the primary IAM delegation in my customer profile is network-team-across-envs vs systems-team-across-envs &mdash; env-first would force per-env IAM bindings for those teams instead of inheritance.

**C. Role-first without composite keys &mdash; nested map with recursive resource block.**
Rejected. I tried the Terraform recursive folder module pattern in earlier work; the added complexity of nested-map propagation outweighs the string-concat savings. Composite keys in a flat map are boring and correct.

**D. Ship without `HUB` in the reference tree &mdash; leave it as `custom_folders` for LZs that need it.**
Rejected. Every LZ in the portfolio needs a HUB. Making it a default is the right call; LZs that don't need it override with `has_environments = false` and skip the HUB project creation.

## Controls this decision supports

Language convention: this ADR uses "supports controls typically found in ..." rather than "complies with". Precise clause IDs are consolidated in [`../security/control-mapping.md`](../security/control-mapping.md).

- **NIS2** &mdash; access control and network security areas (Art. 21). Ownership split (Reason 1) supports separation-of-duties requirements; policy inheritance (Reason 2) enables layered network + workload guardrails.
- **ISO/IEC 27001 &amp; 27002** &mdash; **segregation of duties** is directly addressed by Reason 1 (HostPrj admins vs ServicePrj admins). Network controls area is addressed at Scale 2 (see [ADR-0009](0009-layered-segmentation-hierarchy-first.md)).
- **NIST CSF** &mdash; PR (Protect) function, particularly access control categories.
- **NIST SP 800-53** &mdash; access control family (least privilege, separation of duties).
- **CIS Google Cloud Foundation Benchmark** &mdash; IAM section principles (least-privilege bindings at appropriate scope).
- **Google Cloud Architecture Framework** &mdash; security pillar (separation of environments, defense-in-depth).
- **Zero Trust principles** &mdash; explicit administrative domain boundaries; no cross-domain implicit trust.

## Maturity path

**Current implementation** &mdash; role-first with `HUB` flat, `HostPrj` / `ServicePrj` env-split PRO/PRE/DEV. Supports enterprise workloads with clear team-based separation.

**Enhanced**:
- Add per-BU sub-folders under each env grandchild (e.g. `HostPrj/PRO/BU-A`, `HostPrj/PRO/BU-B`) when a single PRO env hosts multiple business units with independent operators. Extends depth to 4.
- Add hierarchical firewall policies at `HostPrj` and `ServicePrj` folder scope to enforce baseline network / workload rules that individual project firewalls cannot override.
- Add IAM Conditions (`resource.type` or tag-based) so per-team grants at the folder level are further scoped by resource type.

**High-isolation option** (per-env sovereign folders for regulated tenants):
- Add a `LandingZones/Regulated/<env>` parallel sub-tree with independent HUB, HostPrj, ServicePrj, and stricter policy attach points.
- Access Context Manager access levels on the regulated sub-tree.
- Assured Workloads for the regulated projects.

This progression is documented in [`../security/maturity.md`](../security/maturity.md).

## References

- [ADR-0005](0005-folder-per-platform-project.md) &mdash; sibling decision: the `Platform` sub-tree with 1:1 folder-per-project.
- [ADR-0008](0008-ingress-bypasses-perimeter-appliance.md) &mdash; why the HUB (with its FortiGate appliance) is not in the path for public ingress.
- [ADR-0009](0009-layered-segmentation-hierarchy-first.md) &mdash; the three-scale segmentation model that this ADR implements at Scale 1.
- [ADR-0010](0010-single-shared-perimeter-hub.md) &mdash; why HUB is flat (shared across environments) rather than env-split.
- [`../architecture.md`](../architecture.md) &mdash; the v0.2.0 folder tree.
- [`../../stacks/10-folders/README.md`](../../stacks/10-folders/README.md) &mdash; composite keys convention, `reference_landing_zone_children` and `reference_landing_zone_environments` variables.
- [GCP Shared VPC overview](https://cloud.google.com/vpc/docs/shared-vpc) &mdash; the host/service pattern this sub-tree encodes.
