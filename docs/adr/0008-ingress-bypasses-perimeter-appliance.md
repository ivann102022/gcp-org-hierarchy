<!--
File:        docs/adr/0008-ingress-bypasses-perimeter-appliance.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0008: Public ingress bypasses the perimeter appliance by design

**Status**: Accepted
**Date**: 2026-08-07
**Deciders**: Ismael Cruz
**Tags**: gcp, ingress, perimeter, fortigate, cloud-armor, load-balancer, tier-0-boundary

## Context

The Tier 2 landing zone deploys a **FortiGate perimeter appliance** in `pnet-hub` (`gcp0-prj-emp-pnet-hub-01`). Its role is:

- Handle **egress** traffic (workload-initiated outbound connections) &mdash; inspection, URL filtering, IPS.
- Handle **east-west** traffic (inter-tenant, inter-environment) &mdash; enforce inspection between hosts.
- Terminate **admin inbound** (IPSec VPN to on-prem management).

An intuitive question at design time: **should public ingress also traverse the FortiGate?** The naive "single perimeter" instinct says yes. In practice, GCP's architecture makes this impossible for the primary public ingress path, and even where technically possible it would degrade the design.

Public ingress in enterprise GCP terminates via **Global External Load Balancers** (Cloud Load Balancing) + **Cloud Armor** (WAF, DDoS, geo-blocking) + optional **Certificate Manager** for TLS. These are Google-managed services that terminate at Google's edge (Front End Global Load Balancer) and forward to backends via Google's internal network. Key constraints:

1. **Global LB backends cannot be a self-managed NVA** (like FortiGate). The backend types are `INSTANCE_GROUP`, `NETWORK_ENDPOINT_GROUP` (with subtypes: GCE_VM_IP_PORT, INTERNET_FQDN_PORT, INTERNET_IP_PORT, SERVERLESS, PRIVATE_SERVICE_CONNECT), and `BACKEND_BUCKET`. There is no "route this to a FortiGate NVA and let it forward" backend type. The architecture is prescriptive.

2. **Cloud Armor + Google's edge already provide** DDoS mitigation, WAF (with pre-tuned OWASP rulesets), TLS termination, geographic filtering, adaptive bot management. Layering a FortiGate afterward duplicates these capabilities at strictly worse scale (a FortiGate HA pair can handle a fraction of what Google Front End does).

3. **Latency**: adding a FortiGate hop between the Global LB and the backend adds inspection-time latency to every request. For high-QPS workloads (APIs, web frontends), this is measurable.

4. **Stateful chokepoint**: the FortiGate is a stateful device; every ingress connection consumes a session slot. Public ingress traffic patterns can exhaust sessions in ways egress cannot (bursty, high fan-out, session-per-request). Sizing the FortiGate for ingress bursts is expensive.

## Decision

**Public ingress terminates in `pingress` and bypasses the FortiGate perimeter appliance.**

Architecture:

- The `pingress` project (`gcp0-prj-emp-pingress-01`, in `Platform/Ingress` folder per [ADR-0005](0005-folder-per-platform-project.md)) hosts a dedicated **VPC Ingress** with its own public IP allocation.
- Global External LBs, Cloud Armor security policies, and TLS certificates are provisioned in `pingress` (by the future `gcp-ingress-baseline`, Tier 1).
- Backend services (workloads consuming public ingress) live in tenant projects (host projects under `LandingZones/HostPrj/<env>`, service projects under `LandingZones/ServicePrj/<env>`).
- Traffic from Global LBs in `pingress` reaches backends via **Private Service Connect (PSC)** or **internal LB** paths &mdash; not via the FortiGate.

Consequence: `pingress` has its own Internet ingress path (separate from the HUB's Internet egress path via FortiGate). The two Internet arrows in the network topology diagram are intentional:

- **`pnet-hub` &harr; Internet**: north-south egress + admin inbound (VPN). FortiGate in the path.
- **`pingress` &rarr; Internet**: public ingress via Global LB + Cloud Armor + WAF at Google edge. FortiGate NOT in the path.

## Consequences

**Positive**:

- **Scale**: public ingress capacity is Google's edge capacity, not a FortiGate HA pair.
- **Latency**: no extra inspection hop on the ingress path.
- **Security**: Cloud Armor + Google's edge protection are best-in-class for public ingress (DDoS, WAF, bot management). Adding a FortiGate would duplicate poorly.
- **Cost**: no FortiGate session-slot sizing for ingress bursts.
- **Aligned with GCP-native pattern**: this is what Google recommends for enterprise deployments.

**Negative**:

- **Two Internet paths to reason about**. Operators must understand that `pnet-hub` (egress/admin) and `pingress` (public ingress) are separate boundary points. Documented explicitly in the architecture and the network topology diagram.
- **The FortiGate is not the "single perimeter"**. Someone coming from a traditional on-prem model may resist this. Mitigated by this ADR and the network topology diagram.
- **East-west from `pingress` to backend workloads bypasses the FortiGate too**. Traffic goes via PSC / internal LB, which are Google-managed paths &mdash; not through the FortiGate. This is by design (see above) but means east-west inspection between "public-facing backend" and "internal workload" happens at Cloud Armor + host-level firewalls, not at the FortiGate. Trade-off accepted.

**Neutral**:

- **Admin ingress (IPSec VPN)** still terminates at the FortiGate (in the HUB). This ADR only covers **public** ingress via Global LB. VPN traffic from on-prem admin networks continues to traverse the FortiGate.
- **Internal-facing services** (no public ingress) do not touch `pingress` at all &mdash; their inter-tenant traffic goes host-to-host via the HUB (FortiGate east-west). This ADR does not change that.

## Alternatives considered

**A. Route public ingress through the FortiGate.**
Rejected: architecturally impossible with Global LBs (no self-managed NVA backend type). Even if possible via regional LBs + custom routing, the design would trade Google's edge scale for a stateful chokepoint. Loses on every dimension (scale, latency, cost, security).

**B. Deploy Cloud Armor + WAF in the HUB VPC, keep ingress terminating there.**
Rejected: Cloud Armor attaches to LB backend services, not to a VPC directly. To "put Cloud Armor in the HUB" would still require the LBs in the HUB &mdash; and then the FortiGate downstream still cannot be the LB backend. Same constraint as (A) in different clothing.

**C. Use only `pingress` VPC with no separate HUB.**
Rejected: HUB has orthogonal responsibilities (egress inspection + east-west + VPN termination) that don't belong with public ingress. Splitting them is correct.

**D. Put public ingress LBs in each tenant project instead of centralised `pingress`.**
Rejected: fragments Cloud Armor policy management (one policy per tenant instead of shared org-wide policies), fragments TLS certificate management, and loses the audit-single-project property. Central `pingress` is the right consolidation.

## Controls this decision supports

Language convention: this ADR uses "supports controls typically found in ..." rather than "complies with". Precise clause IDs are consolidated in [`../security/control-mapping.md`](../security/control-mapping.md).

- **NIS2** &mdash; network security and threat detection areas (Art. 21). Cloud Armor provides WAF + DDoS + bot management at Google's edge; the perimeter appliance covers egress and cross-domain inspection separately (per [ADR-0010](0010-single-shared-perimeter-hub.md)).
- **ISO/IEC 27001 &amp; 27002** &mdash; network controls, especially perimeter security and management of network services. Two distinct perimeter roles clearly separated (public ingress vs egress/east-west).
- **NIST CSF** &mdash; PR (Protect) and DE (Detect) functions; particularly infrastructure resilience for public-facing services (Google Front End provides scale independent of self-managed capacity).
- **CIS Google Cloud Foundation Benchmark** &mdash; guidance on Global LB configuration, Cloud Armor policies, TLS.
- **OWASP ASVS / Top 10** &mdash; Cloud Armor pre-tuned rulesets cover common ingress-vector attacks.
- **Google Cloud Architecture Framework** &mdash; security pillar, especially the recommended pattern for public-facing services (edge protection + private backends).

## Maturity path

**Current implementation** &mdash; public ingress via Global LB + Cloud Armor + WAF in `pingress`, backends reached via Private Service Connect / internal LB. Perimeter FortiGate handles egress + east-west + VPN only.

**Enhanced**:
- Add IAP (Identity-Aware Proxy) for admin ingress paths that today go through VPN + FortiGate &mdash; specific admin apps can move to context-aware access via IAP without a VPN, further reducing FortiGate scope.
- Add reCAPTCHA Enterprise integration on Cloud Armor policies for user-facing endpoints.
- Add Cloud Armor adaptive protection for automated anomaly detection.
- Add Cloud CDN in front of Global LBs for cacheable content (reduces origin traffic + adds edge caching layer).

**High-isolation option** (dedicated perimeters per exposure tier):
- Separate `pingress` into multiple projects by exposure tier: `pingress-internet` (public internet), `pingress-partner` (B2B partner traffic via mutual TLS), `pingress-admin` (management ingress via IAP + strict allowlist).
- Independent Cloud Armor policies, TLS certificates, and audit trails per exposure tier.
- Reduces blast radius of a misconfiguration in one tier.

**BeyondCorp option** (context-aware access as the primary perimeter for admin flows):
- Move admin ingress fully to IAP + BeyondCorp Access Context Manager.
- Remove VPN termination from FortiGate for admin users (workload-to-workload VPN with on-prem remains).
- Users authenticate + context-check at every request rather than trusting a VPN tunnel.

This progression is documented in [`../security/maturity.md`](../security/maturity.md).

## References

- [../architecture.md](../architecture.md) &mdash; section "Why public ingress bypasses the perimeter appliance".
- [ADR-0005](0005-folder-per-platform-project.md) &mdash; the `Ingress` folder that holds `pingress`.
- [ADR-0006](0006-landing-zones-hostprj-serviceprj-env-split.md) &mdash; the HUB folder that holds the FortiGate perimeter appliance.
- [ADR-0009](0009-layered-segmentation-hierarchy-first.md) &mdash; the three-scale segmentation model. Public ingress bypass is a Scale 2/3 decision (dedicated VPC + distributed authorization) reserving Scale 2 HUB for cross-domain transit.
- [ADR-0010](0010-single-shared-perimeter-hub.md) &mdash; the FortiGate HUB scope explicitly excludes public ingress, which is why single HUB stays sized for egress/east-west only.
- [GCP Global External Load Balancer backends](https://cloud.google.com/load-balancing/docs/backend-service) &mdash; canonical reference for the backend type constraint.
- [Cloud Armor overview](https://cloud.google.com/armor) &mdash; the WAF/DDoS layer that terminates at Google's edge.
- Future repo `baseline-projects/gcp-ingress-baseline/` (Tier 1, placeholder today) &mdash; will materialise VPC Ingress + Global LBs + Cloud Armor + TLS certs inside `pingress`.
