<!--
File:        docs/adr/0010-single-shared-perimeter-hub.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0010: Single shared perimeter HUB across environments

**Status**: Accepted
**Date**: 2026-08-08
**Deciders**: Ismael Cruz
**Tags**: gcp, hub, perimeter, fortigate, cost, trade-off, tier-0-boundary

## Context

In my landing zone designs, the perimeter appliance (typically a FortiGate HA cluster) lives in a single project (`pnet-hub`) inside a single folder (`LandingZones/HUB`) and is shared across all environments &mdash; PRO, PRE, and DEV all traverse the same perimeter for the traffic that reaches it.

The obvious alternative is HUB-per-environment: three independent perimeter projects, three independent FortiGate HA clusters, three independent public IP allocations, three independent VPN terminations. That design offers stronger environmental isolation (a compromise in one perimeter does not affect the others) at meaningfully higher cost.

This ADR documents why I have consistently chosen the single-HUB pattern and what conditions would change that decision.

## Decision

**A single shared HUB (single project, single perimeter appliance cluster) is used across PRO / PRE / DEV.**

The folder shape encodes this: `LandingZones/HUB` is a flat folder (no environment sub-folders), unlike `LandingZones/HostPrj` and `LandingZones/ServicePrj` which fan out into `PRO / PRE / DEV` grandchildren (see [ADR-0006](0006-landing-zones-hostprj-serviceprj-env-split.md)).

## Rationale (two layers)

The decision has two layers of justification. Both are needed to make the choice defensible &mdash; the economic argument alone reads as "chose the cheap option"; the architectural argument alone reads as detached from real-project constraints. Together they read as conscious design.

### Layer 1 &mdash; Economic

Deploying HUB-per-environment triples the perimeter cost:

- **3&#x00D7; FortiGate HA clusters** (or equivalent for other NGFW vendors). Licensing is per-VM; each cluster is at least 2 VMs; three clusters is 6 licensed VMs. FortiGate licensing at enterprise SKUs is meaningful money.
- **3&#x00D7; public IP allocation** and 3&#x00D7; VPN termination endpoints. Cloud VPN + BGP routing per env.
- **3&#x00D7; operational load** &mdash; three change windows, three upgrade cycles, three break-glass procedures for a device that mostly does the same thing in each env.

For most of the customers I have worked with, that additional cost does not translate into proportional risk reduction. The workloads in DEV do not warrant their own dedicated perimeter cluster.

### Layer 2 &mdash; Architectural

The economic argument only works because the perimeter appliance is **not** the sole segmentation control. Per [ADR-0009](0009-layered-segmentation-hierarchy-first.md), the architecture uses a three-scale segmentation model:

- **Scale 1 (Resource Hierarchy)** separates administrative domains (HostPrj vs ServicePrj, per-env sub-folders) via folder IAM inheritance.
- **Scale 2 (VPC / Shared VPC)** creates independent connectivity domains per environment (each `pnet-<env>` is its own host project with its own Shared VPC).
- **Scale 3 (Distributed Firewall)** enforces microsegmentation via GCP's implicit-deny model &mdash; each VPC's firewall policies handle intra-domain authorization without the perimeter's involvement.

The perimeter appliance is therefore reserved for one specific job: **flows that transit between domains and require inspection** (external egress, cross-org east-west that must be inspected, admin VPN termination). Intra-VPC and intra-tenant east-west traffic never reaches the perimeter &mdash; it is enforced at Scale 3 by the distributed firewall.

With this scoping:

```
                  Security enforcement
                          │
              ┌───────────┴───────────┐
              │                       │
              ▼                       ▼
    Distributed enforcement     Central perimeter
      (GCP Cloud Firewall)          (FortiGate)
              │                       │
              ▼                       ▼
    Microsegmentation           Transit between domains
    (intra-VPC, intra-tenant)   (external egress, VPN, cross-domain)
```

The perimeter carries the volume of cross-domain flows, not the volume of all workload traffic. That volume does not scale linearly with the number of environments &mdash; a single HUB sized for the cross-domain load handles PRO + PRE + DEV combined without stress.

## Trade-offs

I explicitly accept the following in exchange for the cost savings:

- **The perimeter is a shared dependency**. A misconfiguration or compromise in the FortiGate affects all environments. Mitigated by: (a) the FortiGate's own HA (active-passive); (b) tight change management on the HUB stack &mdash; the HUB has the strictest change window in the LZ; (c) the distributed firewall continues to enforce microsegmentation even if the perimeter is degraded (workloads within a tenant do not depend on the FortiGate for local reachability).
- **Weaker environmental isolation** than HUB-per-env. A DEV workload that somehow exploits the FortiGate reaches the same appliance PRO traffic traverses. Mitigated by: DEV egress paths and rules are the same as PRO but with looser destination allowlists; the concern is exploiting the appliance itself, not the policy. That risk is bounded by keeping the FortiGate patched and its config reviewed &mdash; same discipline whether shared or split.
- **HUB change windows serialize across environments**. Upgrading the FortiGate cannot be "just DEV first" because PRO uses the same cluster. Mitigated by the FortiGate HA passive node being upgraded first (via the HA failover process) &mdash; the operational impact is on the HUB team, not on workload teams.

## Alternatives considered

**A. HUB-per-environment (`HUB-PRO`, `HUB-PRE`, `HUB-DEV`, each with its own FortiGate HA cluster).**
Rejected for the reasons above. Legitimate design and technically stronger for isolation; the additional cost and operational overhead do not justify the marginal risk reduction for the customer profiles I have worked with.

**B. Single HUB project with multiple firewall clusters (still one project, still one folder, but separate FortiGate instances per env).**
Rejected. Keeps the shared blast radius at the project / IAM / VPC level (still one Shared VPC hub network) while paying most of the multi-cluster cost. Neither cheaper nor stronger &mdash; worst of both worlds.

**C. No perimeter appliance &mdash; rely entirely on GCP Cloud Firewall + Cloud Armor + IAP.**
Rejected for this LZ family (Fortinet LZs). Cloud-native perimeter is a legitimate design for specific customer segments (cloud-first, no on-prem, no vendor commitment to Fortinet). I have delivered that variant in other projects; it lives as a separate LZ in the portfolio (or would &mdash; the `gcp-lz-cloud-native-perimeter` variant is not currently in the portfolio). When the customer has an existing Fortinet investment or requires vendor NGFW for compliance, the FortiGate HUB is the design.

**D. HUB per business unit instead of per environment.**
Rejected. Same cost profile as HUB-per-env; no incremental isolation benefit; introduces cross-team ownership complexity for the perimeter appliance.

## When to reconsider this decision

Cases where I would move to HUB-per-environment despite the cost:

- **Regulated PRO with dedicated compliance perimeter** (some PCI-DSS interpretations, some sovereign-cloud requirements, some GxP interpretations). Physical/logical isolation of the PRO perimeter is required by audit.
- **Multi-tenant SaaS where DEV and PRO belong to different customer trust domains** &mdash; DEV traffic sharing infrastructure with PRO traffic is unacceptable to the SaaS operator's own compliance obligations.
- **Perimeter throughput saturation** &mdash; if PRO alone saturates a HUB sized for PRO+PRE+DEV combined. In practice I have not hit this; workload traffic dominates over perimeter traffic when microsegmentation is doing its job at Scale 3.

## Controls this decision supports

Language convention: this ADR uses "supports controls typically found in ..." rather than "complies with". Precise clause IDs are consolidated and verified in [`../security/control-mapping.md`](../security/control-mapping.md).

- **NIS2** &mdash; network security area (Art. 21). Perimeter inspection covered for cross-domain transit; distributed enforcement covered for intra-domain via Scale 3 (see [ADR-0009](0009-layered-segmentation-hierarchy-first.md)).
- **ISO/IEC 27001 &amp; 27002** &mdash; network controls area, security of network services. Central management of a single perimeter appliance simplifies operational audit; the trade-off is the shared blast radius.
- **NIST CSF** &mdash; PR (Protect) function, network integrity via segmentation. Combined Scale 2 (VPC) + Scale 3 (distributed firewall) address network integrity even when the perimeter is a shared dependency.
- **NIST SP 800-53** &mdash; system and communications protection family (perimeter and boundary protection controls).
- **CIS Google Cloud Foundation Benchmark** &mdash; ensure the default VPC network is not in use, restrict egress flows through the perimeter (Section 3 area).
- **Google Cloud Architecture Framework** &mdash; security pillar, defense-in-depth (the single HUB is one layer; distributed firewall is another).

## Controls this decision does NOT fully support

Honesty for the reader &mdash; single shared HUB is a defensible design, but there are compliance regimes for which it is not sufficient on its own:

- **PCI-DSS** (CDE isolation requirements) &mdash; requires demonstrably-isolated CDE perimeter. Shared perimeter across environments does not satisfy this by itself; if PCI CDE is in scope, move to HUB-per-CDE-scope per the maturity path below.
- **Sovereign-cloud regulations** requiring per-jurisdiction perimeter &mdash; not satisfied by a single shared HUB. Jurisdictional isolation requires physically or contractually independent perimeter infrastructure.
- **Some interpretations of GxP** (regulated pharma / life sciences) &mdash; may require dedicated production perimeter for validated systems. Move PRO to a dedicated HUB.

## Maturity path

**Current implementation** &mdash; single shared HUB. Fits enterprise workloads with layered segmentation from [ADR-0009](0009-layered-segmentation-hierarchy-first.md). Cost / operational efficiency prioritised.

**Enhanced** (retain single perimeter appliance, strengthen operational controls):
- Add hierarchical firewall policies at folder scope so PRO-destined flows have stricter rules than DEV even through the same appliance.
- Add per-environment IAM condition constraints on the HUB project so operators managing DEV cannot inadvertently affect PRO.
- Increase audit granularity: per-env log labels on FortiGate traffic logs, per-env dashboards, per-env alert channels.

**High-isolation option** (HUB-per-environment):
- Deploy independent FortiGate HA cluster per environment (`HUB-PRO`, `HUB-PRE`, `HUB-DEV`).
- Independent public IP allocations, independent VPN terminations, independent change windows.
- Accept the 3&#x00D7; cost profile in exchange for full environmental isolation.
- Warranted when: PCI CDE in scope, sovereign-cloud requirements, multi-tenant SaaS with different customer trust domains per environment.

**Dedicated CDE / regulated-workload perimeter** (specific compliance overlay):
- Add a fourth HUB (`HUB-REGULATED`) alongside the shared HUB, dedicated to CDE or regulated-workload traffic.
- Distinct firewall cluster, distinct rules, distinct audit trail scoped to the compliance obligation.
- Regulated workloads bypass the shared HUB entirely.

This progression is documented in [`../security/maturity.md`](../security/maturity.md).

## References

- [ADR-0006](0006-landing-zones-hostprj-serviceprj-env-split.md) &mdash; the folder shape that puts HUB flat (not env-split) while HostPrj and ServicePrj are env-split.
- [ADR-0008](0008-ingress-bypasses-perimeter-appliance.md) &mdash; sibling decision: public ingress bypasses the HUB entirely (Google edge handles it). This further limits the traffic volume the HUB has to handle.
- [ADR-0009](0009-layered-segmentation-hierarchy-first.md) &mdash; the three-scale segmentation model that makes single-HUB defensible.
- [`../architecture.md`](../architecture.md) &mdash; section "Why single HUB".
- Sibling LZ [`../../../../landing-zones/gcp-lz-fortinet-multiproject/README.md`](../../../../landing-zones/gcp-lz-fortinet-multiproject/README.md) &mdash; the LZ that materialises the FortiGate HA cluster in `pnet-hub`.
