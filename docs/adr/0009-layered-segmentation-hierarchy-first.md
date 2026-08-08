<!--
File:        docs/adr/0009-layered-segmentation-hierarchy-first.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0009: Layered segmentation &mdash; hierarchy is the first line, not the network

**Status**: Accepted
**Date**: 2026-08-08
**Deciders**: Ismael Cruz
**Tags**: gcp, segmentation, hierarchy, vpc, distributed-firewall, perimeter, portfolio-principle

## Context

Every enterprise GCP design I have delivered has faced the same question at kickoff: **where do we put the segmentation boundaries?** The default (and wrong) instinct is to answer with the network alone: "we'll put a firewall in the middle, put things on either side, done." That answer collapses the moment the architecture has more than one governance domain, more than one team operating it, or more than one lifecycle to respect.

In my architectures I have deliberately structured segmentation as a **three-scale model**, and this ADR captures that model as an explicit portfolio principle so every subsequent decision (folder shape, project multiplication, single HUB, ingress path, ...) has a common frame of reference.

The three scales are not layers of a single tool &mdash; they are three distinct planes with three distinct questions and three distinct sets of GCP resources.

## Decision

**Segmentation is expressed at three scales, each answering a different question:**

### Scale 1 &mdash; Macrosegmentation (Resource Hierarchy)

Question: **which administrative, security and governance domains do I want to separate?**

Tools: Folders + Projects + IAM (inherited down the tree) + Organization Policies + delegated administration.

**Folder and Project play distinct roles at this scale and must be understood together**:

- **Folders** establish governance and delegation domains &mdash; they are attach points for IAM inheritance, org policies, and hierarchical firewall policies. A Folder is a *boundary declaration*.
- **Projects** materialise resource, lifecycle and administrative boundaries within those domains &mdash; APIs enabled per Project, quotas per Project, distinct billing attribution per Project, distinct state ownership per Project. A Project is a *container of resources* with its own IAM surface, subordinate to the enclosing Folder's inheritance.

Scale 1 segmentation does not end at Folders &mdash; Folder and Project work together as one scale. A well-designed Scale 1 has the right Folders (governance and delegation), the right Projects inside those Folders (resource and lifecycle boundaries), and coherent 1:1 or 1:N relationships between them (see ADR-0005 for the platform-tier choice).

This is the **first frontier** &mdash; it segments before a single VPC exists. In my architectures, this is where:

- HostPrj vs ServicePrj lives (different administrative domains: Network+Security teams operate HostPrj; Systems+Applications teams operate ServicePrj).
- PRO / PRE / DEV split lives (different policy strengths per environment; PRO gets the strongest, DEV gets the loosest). Crucially, this separation begins at the Resource Manager layer (distinct Projects) before it appears at the network layer &mdash; distinct IAM, distinct quotas, distinct APIs, distinct billing lines per environment, not just distinct VPCs.
- 1:1 folder-per-platform-project lives (granular IAM scoping so `roles/dns.admin` on `DNS` folder applies only to `pdns`).

The hierarchy is not decoration around the network &mdash; it is the primary control surface.

### Scale 2 &mdash; Network segmentation (VPC)

Question: **which connectivity domains do I want to create?**

Tools: VPC, Shared VPC, subnets, routing, VPC Peering, NCC, VPN, Interconnect.

In my architectures, this is where the HUB (perimeter appliance) lives; where each host project's Shared VPC lives; where the peering / NCC topology between HUB and spokes lives.

**Important GCP-specific detail** (worth documenting because it drives design decisions later): a GCP VPC **does not have a global CIDR**. The address space belongs to the subnets, not to a supernet associated with the VPC. In AWS you write `VPC 10.0.0.0/16` and subnets subdivide it; in GCP each subnet stands on its own with its own CIDR. This affects how connectivity domains are composed and how peering / NCC advertise CIDRs.

### Scale 3 &mdash; Microsegmentation (Distributed Firewall Policies)

Question: **even if reachability exists, who is authorized to talk to whom?**

Tools: VPC firewall rules, hierarchical firewall policies, tag-based rules, network firewall policies.

This is where the subtle GCP model matters, and where a common mis-formulation must be avoided:

- **Routing**: within a single GCP VPC, subnets **do have reachability** &mdash; GCP creates subnet routes automatically. Two subnets in the same VPC can route to each other.
- **Firewall policy**: GCP applies **implicit deny for ingress** &mdash; even though routing reaches, traffic is blocked unless an explicit rule permits.

The correct formulation is therefore: **"subnets have routing reachability but no default authorization."** Do not say "subnets are isolated by default" &mdash; that conflates routing with policy, and misses that the isolation is enforced by the distributed firewall, not by the topology.

## The scales are connected, not siloed

The three scales are distinct concerns with distinct primary tools, but they are **not independent silos**. Scale 1 provides the scope over which Scale 3 rules can inherit.

The connective tissue is **Hierarchical Firewall Policies (HFPs)**. An HFP is a Scale 3 mechanism (distributed firewall rule) that attaches at Scale 1 scope (Organization or Folder) and propagates by inheritance down the hierarchy to VPCs of descendant Projects. Rules with `goto_next` action delegate evaluation further down; rules with terminal action are non-overridable by descendants.

Concretely: an HFP attached at the `LandingZones/HostPrj` folder governs firewall behaviour for every VM interface using any Host Project's VPC underneath &mdash; PRO, PRE, DEV. That inheritance is what makes the "hierarchy first" principle operationally meaningful for network policy, not only for IAM and org policies.

Consequence: **getting Scale 1 right today is a precondition for expressing effective Scale 3 policy tomorrow**. The folder shape decisions in ADR-0005 and ADR-0006 are causal for what `30-org-policies` (planned) and future HFP-based policies can express cleanly via inheritance.

## The portfolio principle

Made explicit as a one-sentence rule referenced across every other ADR:

> **The architecture does not delegate segmentation exclusively to the network. The first frontier is established via Resource Manager (Folders + Projects). The second is via VPC / Shared VPC connectivity domains. Fine-grained authorization is enforced by distributed firewall controls &mdash; often via Hierarchical Firewall Policies that inherit down the Scale-1 hierarchy. The centralized perimeter is reserved for the flows that require transit and inspection between domains.**

This principle is why the portfolio's Tier 0 shape looks the way it does, and why a single shared perimeter HUB (see [ADR-0010](0010-single-shared-perimeter-hub.md)) is a defensible design rather than a corner-cutting compromise.

## Rationale

I have used this three-scale model consistently because it produces designs that survive first contact with real operational teams:

- **The hierarchy scale addresses the human boundary** &mdash; who operates what, who can grant access to what, who owns the change window for what. GCP's IAM inheritance through folders makes this the highest-leverage control surface.
- **The network scale addresses the topology boundary** &mdash; where the connectivity domains live, how they interconnect, where the perimeter appliance sits.
- **The microsegmentation scale addresses the authorization boundary** &mdash; who is actually allowed to talk to whom, even inside the same VPC.

Collapsing any two of these into one loses expressiveness. Collapsing all three into "the firewall" gives you a design where the FortiGate becomes both the perimeter *and* the microsegmentation *and* the governance boundary &mdash; which is exactly the design that fails when workloads grow past a single team.

## Trade-offs

- **Reader complexity**: someone new to the portfolio has to understand three scales instead of "the firewall handles it". Mitigated by making the three-scale model explicit up front (this ADR + a section in `docs/architecture.md`).
- **Coordination cost**: changes at Scale 1 (hierarchy) involve org-level actors; changes at Scale 3 (firewall rules) involve project-scoped operators. Different change velocities per scale. Deliberate &mdash; each scale changes at its natural cadence.
- **GCP-specific reasoning**: this model leans on GCP's default-deny distributed firewall. In AWS/Azure where subnet-level defaults differ (they route AND allow by default), the same reasoning applies but the tooling is different (subnet route tables + NACLs + security groups in AWS; UDR + NSG in Azure). Portfolios for those CSPs use the same three-scale model with per-CSP tool substitution.

## Alternatives considered

**A. Single-scale segmentation via perimeter firewall only.**
Rejected. This is the "everything is east-west traffic and everything must traverse the FortiGate" model. Works at small scale; collapses when: (a) two teams need different policy on the same VPC, (b) the FortiGate saturates before workloads do, (c) audit needs to prove separation of duties between network and workload teams and the firewall alone cannot express it. Every enterprise I have worked with has already hit at least one of these three failure modes.

**B. Two-scale segmentation (network + microsegmentation, no hierarchy).**
Rejected. This is the "flat GCP with one big project" model &mdash; sometimes seen in startups migrating to enterprise. Loses IAM inheritance, loses per-project quota, loses per-project billing visibility, and collapses the governance surface. The hierarchy scale is not optional at enterprise scale.

**C. Four-scale segmentation (add a "data plane" scale via VPC-SC, Private Service Connect, Assured Workloads).**
Not rejected &mdash; deferred. VPC Service Controls, PSC, and Assured Workloads are legitimate additional segmentation controls (data exfiltration boundaries, private connectivity boundaries, compliance boundaries). I have used them in specific engagements (GDPR-scoped workloads, financial services). But they add value on top of the three scales, not in place of one. When the portfolio's `30-org-policies` and future baselines mature, adding a "Scale 4 &mdash; data plane segmentation" section is a natural extension.

## Controls this decision supports

Framework language convention: this ADR uses "supports controls typically found in ..." and "contributes to the implementation of ...". A folder shape or firewall model does not by itself make an architecture compliant with any standard &mdash; certification depends on processes, evidence, people, audit, etc. Precise clause IDs are consolidated and verified in [`../security/control-mapping.md`](../security/control-mapping.md); the references below name the standard and the concept area rather than pinning specific numbered clauses.

The three-scale model is not itself mandated by any framework. It operationalises design principles that are typically expressed as controls in:

- **NIS2** &mdash; risk management measures with layered access control (Art. 21 area). The three scales correspond to distinct access-control planes (hierarchy = who administers; network = who reaches; microseg = who is authorized).
- **ISO/IEC 27001 &amp; 27002** &mdash; areas addressed include network controls, segregation in networks, and segregation of duties. Scale 1 directly addresses segregation of duties (HostPrj administrators vs ServicePrj administrators); Scale 2 and 3 address network controls at different granularities.
- **NIST CSF** &mdash; specifically PR (Protect) function, access control and data security categories.
- **NIST SP 800-53** &mdash; access control and system and communications protection families.
- **CIS Google Cloud Foundation Benchmark** &mdash; VPC and firewall configuration recommendations (Section 3 area).
- **Google Cloud Architecture Framework** &mdash; security pillar, defense-in-depth patterns.
- **Zero Trust principles** &mdash; explicit authorization at each layer, no implicit trust between scales.

If PCI-DSS scope enters the architecture, an additional Scale 4 (data-plane segmentation via VPC-SC + dedicated perimeter) is warranted &mdash; see the deferred alternative (C) above and the maturity path below.

## Maturity path

The current three-scale implementation supports the workloads I have deployed in enterprise customer engagements. For customers with stricter requirements, the architecture evolves without discarding the current design:

**Current implementation** &mdash; three scales as described in this ADR. Sufficient for standard enterprise workloads under NIS2 / ISO 27001 baseline.

**Enhanced**:
- Add hierarchical firewall policies at folder scope (`HostPrj`, `ServicePrj`) to enforce cross-project baseline rules that individual VPC firewalls cannot override.
- Add tag-based firewall rules using Resource Manager tags (see [`60-tags`](../../stacks/60-tags/README.md), planned) for workload-classification-driven microsegmentation.
- Automate policy validation via Policy Controller / Config Sync / OPA-style gating on every apply.

**High-isolation option** (Scale 4 &mdash; data-plane segmentation):
- Introduce VPC Service Controls perimeters around sensitive data projects (`plogs`, `pmgm`, regulated workloads).
- Introduce Private Service Connect for all internal service consumption &mdash; no traffic leaves the private network fabric.
- Introduce Access Context Manager access levels for context-aware authorization at Scale 3.
- Consider Assured Workloads for regulated tenants (FedRAMP, HIPAA, IL2/4/5, EU sovereign).

This progression is documented in [`../security/maturity.md`](../security/maturity.md).

## References

- [ADR-0005](0005-folder-per-platform-project.md) &mdash; 1:1 folder-per-project is a Scale 1 decision that enables per-project IAM scoping.
- [ADR-0006](0006-landing-zones-hostprj-serviceprj-env-split.md) &mdash; HostPrj/ServicePrj split is a Scale 1 decision that encodes different administrative domains.
- [ADR-0008](0008-ingress-bypasses-perimeter-appliance.md) &mdash; the ingress-bypasses-perimeter design relies on Scale 3 microsegmentation existing.
- [ADR-0010](0010-single-shared-perimeter-hub.md) &mdash; single HUB is defensible *because* Scale 3 microsegmentation handles intra-domain enforcement.
- [`../architecture.md`](../architecture.md) &mdash; section "Layered segmentation".
- [GCP Cloud Firewall documentation](https://cloud.google.com/firewall/docs) &mdash; canonical reference for the implicit-deny model at Scale 3.
