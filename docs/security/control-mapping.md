<!--
File:        docs/security/control-mapping.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Consolidated mapping of architectural decisions in this repo
             to the reference frameworks the portfolio supports. Uses
             hedged language ("supports controls typically found in...")
             deliberately: a Terraform folder or firewall rule does not by
             itself make an architecture compliant with a standard. Precise
             clause IDs must be verified against the current version of
             each framework before quoting them externally.
-->

# Control mapping &mdash; architectural decisions &rarr; frameworks

This document consolidates the mapping between the architectural decisions in this repo (documented per-ADR under [`../adr/`](../adr/)) and the reference frameworks the portfolio deliberately supports.

## Language convention

**A technical control contributes to satisfying a framework requirement. It does not, by itself, make the architecture compliant with that framework.** Compliance depends on processes, evidence, people, audit trails, incident response, and ongoing operation &mdash; not on a Terraform folder existing.

Throughout this repo I use:

- **"Supports controls typically found in ..."** &mdash; the decision provides a technical capability aligned with a framework area.
- **"Contributes to the implementation of ..."** &mdash; the decision is part of, but not sufficient for, meeting a specific control.
- **"Provides a technical control supporting ..."** &mdash; explicit framing that the technical piece is one of several inputs to a control.

I reserve **"compliant with"** for statements backed by an actual audit or certification process. That's a boundary I do not cross in portfolio documentation.

## Verification note

The framework area references below (NIS2 Article X, ISO 27001 clause Y, NIST SP 800-53 control Z) are given at **the level of framework area / family / category** rather than pinning exact clause numbers. Framework versions evolve (ISO 27001:2013 &rarr; 2022 renumbered controls significantly; NIST CSF 1.1 &rarr; 2.0 changed the function set) and pinning outdated clause IDs damages the credibility of the mapping. **Before quoting specific clause IDs externally (customer proposal, audit response, RFP)**, verify against the current published version of each framework.

## Frameworks in scope

The portfolio targets these frameworks by default because they are the ones I have encountered most frequently in enterprise customer engagements:

| Framework | Scope | Relevance |
|---|---|---|
| **NIS2** (EU Directive 2022/2555) | EU operators of essential services + suppliers | Universal for EU enterprise engagements. Art. 21 measures cover most technical controls in this portfolio. |
| **ISO/IEC 27001:2022 + 27002:2022** | Information security management systems (global) | Universally recognised. Annex A control families map cleanly to portfolio decisions. |
| **NIST CSF 2.0** | Risk-based framework, US origin but adopted globally | Function-based structure (Govern / Identify / Protect / Detect / Respond / Recover) is intuitive for cross-framework navigation. |
| **NIST SP 800-53 Rev. 5** | Detailed control catalogue | Where NIST CSF is high-level, 800-53 is control-level detail. Referenced for specific technical mappings. |
| **CIS Google Cloud Foundation Benchmark** | Prescriptive per-resource for GCP | Direct alignment with Terraform decisions on org policies, IAM, logging, VPC. |
| **Google Cloud Architecture Framework** | Google's own guidance on well-architected GCP | Peer reference for design patterns; not a compliance framework but a design authority. |

Additional frameworks referenced when the specific decision touches their scope:

| Framework | When it applies | Referenced by |
|---|---|---|
| **PCI-DSS** | Payment card data handling | ADR-0010 (single HUB has PCI limitations) |
| **GDPR** | Personal data processing | Referenced in export/retention decisions (baselines) |
| **ENS** (Esquema Nacional de Seguridad) | Spanish public sector | Portfolio-optional for sector-público engagements |

## Decision &rarr; framework matrix

Rows = architectural decisions from this repo's ADRs. Columns = framework areas. Cell content = *how the decision supports controls in that area*. Cells marked `—` indicate no meaningful contribution (either not the framework's scope, or not what this decision provides).

### Segmentation & structure

| Decision | ADR | NIS2 | ISO 27001/27002 | NIST CSF | NIST SP 800-53 | CIS GCP | Google CAF |
|---|---|---|---|---|---|---|---|
| Layered segmentation (hierarchy first) | [0009](../adr/0009-layered-segmentation-hierarchy-first.md) | Art. 21 access control, network security | A.5 access control area, A.8 asset management area, A.6 organization of information security area (segregation of duties) | GV.RM, PR.AA (access control), PR.IR (infrastructure resilience) | AC family (access control), SC family (system and communications protection) | Section 3 (VPC / firewall) area | Security pillar: defense-in-depth |
| 1:1 folder per platform project | [0005](../adr/0005-folder-per-platform-project.md) | Art. 21 access control | A.5 access control, A.8 privileged access | PR.AA (least privilege) | AC-6 (least privilege), AC-3 (access enforcement) | IAM section (least-privilege bindings) | Security pillar: role scope |
| HostPrj / ServicePrj + PRO/PRE/DEV split | [0006](../adr/0006-landing-zones-hostprj-serviceprj-env-split.md) | Art. 21 network security, access control | A.5 access control, A.6 segregation of duties, A.8 asset management | GV.OC (organizational context), PR.AA | AC-5 (separation of duties), AC-6 (least privilege) | IAM + folder recommendations | Security pillar: environmental separation |
| Public ingress bypasses perimeter | [0008](../adr/0008-ingress-bypasses-perimeter-appliance.md) | Art. 21 network security, threat detection | A.8 network security controls area, A.5 access control | PR.IR (infrastructure resilience), DE.CM (continuous monitoring) | SC-7 (boundary protection), SC-5 (denial of service protection) | Load balancer + Cloud Armor sections | Security pillar: edge protection |
| Single shared perimeter HUB | [0010](../adr/0010-single-shared-perimeter-hub.md) | Art. 21 network security | A.8 network security controls | PR.IR, PR.PS (platform security) | SC-7 (boundary protection) | Network / firewall sections | Security pillar: perimeter management (with explicit trade-off) |

### Ownership & lifecycle

| Decision | ADR | NIS2 | ISO 27001/27002 | NIST CSF | NIST SP 800-53 | CIS GCP | Google CAF |
|---|---|---|---|---|---|---|---|
| Platform projects owned by Tier 0 | [0002](../adr/0002-platform-projects-here-not-in-lz.md) | Art. 21 asset management, change management | A.5 governance, A.8 asset management | ID.AM (asset management) | CM family (configuration management) | Project management guidance | Foundation pillar |
| Org log sink in Tier 0, not obs baseline | [0003](../adr/0003-org-sink-in-tier0-not-obs-baseline.md) | Art. 21 incident detection, logging | A.8 logging and monitoring, A.5 access control (least privilege for logging management) | DE.AE (anomalies and events), PR.PT (protective technology, audit capability) | AU-2 (event logging), AU-12 (audit record generation), AC-6 | Logging section (aggregate at org level) | Operational excellence + security pillars |
| WIF in identity-baseline, not Tier 0 | [0004](../adr/0004-no-workforce-identity-federation-here.md) | Art. 21 access control | A.5 access control, A.5 privileged access, A.8 identity management | PR.AA (identity management, access control) | AC-2 (account management), AC-6 (least privilege) | IAM section | Security pillar: least-privilege scoping |

### Engineering / project conventions

| Decision | ADR | Framework relevance |
|---|---|---|
| Two organization modes only (existing / create) | [0001](../adr/0001-two-modes-only-existing-and-create.md) | Engineering decision; no direct framework mapping. Indirectly supports change control (A.5 area). |
| Content rule for `00-org-baseline` | [0007](../adr/0007-content-rule-for-org-baseline.md) | Portfolio convention; no direct framework mapping. Indirectly supports documentation discipline. |

## How to use this document

**When writing a customer proposal or RFP response** referencing this portfolio: use this matrix as the starting point, then verify each cited clause against the current published version of the framework. Do not copy clause IDs from this document into external communications without that verification pass.

**When reviewing an ADR**: check that the "Controls this decision supports" section in the ADR is consistent with the row for that decision in this matrix. Discrepancies mean either the ADR or this matrix needs updating.

**When adding a new ADR**: fill in the row here alongside writing the ADR's own "Controls this decision supports" section. Both are consulted for different purposes (per-ADR for depth, matrix for cross-decision navigation).

**When a framework version changes** (e.g. ISO 27001:2022 &rarr; a future revision): review the matrix for changed clause numbers before referencing them.

## Not covered (explicit gaps)

The following framework areas are relevant to enterprise GCP architectures but are **not currently addressed** by the decisions in this repo. They may be addressed by:

- Future Tier 0 stacks (30-org-policies, 40-org-logging, 50-org-iam, 60-tags) &mdash; not yet shipped.
- Tier 1 baselines &mdash; specifically observability, identity, security baselines.
- Tier 2 landing zones &mdash; workload-level controls.
- Operational processes outside Terraform &mdash; incident response, DR testing, awareness training.

Gaps at the Tier 0 level:

| Framework area | Not yet addressed by this repo | Planned in |
|---|---|---|
| Org-level policy enforcement (NIS2 Art. 21 risk management, ISO A.5 policies) | Yes | `30-org-policies` (planned v0.3.0) |
| Central audit logging enforcement | Partially (this repo's sink integration is deferred to v0.3.0) | `40-org-logging` (planned v0.3.0) |
| Privileged access management | Partially (Org Admin binding, break-glass) | `50-org-iam` (planned v0.4.0) |
| Resource classification / tagging | Yes | `60-tags` (planned v0.4.0) |
| Detection / SIEM integration | No | `gcp-observability-baseline` (Tier 1, shipped v0.1.0 &mdash; scope is central log storage + exports; SIEM ingestion is per-customer) |
| Vulnerability management | No | Not in Terraform scope; operational |
| Incident response | No | Not in Terraform scope; operational |

Being explicit about the gaps is itself a portfolio-quality signal. A reviewer who sees "we do X, we don't yet do Y, here's when Y lands" reads it as honest engineering; a reviewer who sees implicit gaps and unstated assumptions reads it as over-selling.
