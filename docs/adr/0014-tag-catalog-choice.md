<!--
File:        docs/adr/0014-tag-catalog-choice.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0014: Tag catalog choice and opt-in default

**Status**: Accepted
**Date**: 2026-08-08
**Deciders**: Ismael Cruz
**Tags**: gcp, tier-0, tags, resource-manager, governance, opt-in

## Context

GCP Resource Manager tags (`google_tags_tag_key` / `google_tags_tag_value`) enable cross-tier governance patterns:

- **Tag-based IAM Conditions** &mdash; `roles/editor` on this project active only when `environment=prod` tag is present.
- **Tag-based org policy conditions** &mdash; `constraints/compute.vmExternalIpAccess = deny` except when `environment=sandbox`.
- **Tag-based hierarchical firewall rules** &mdash; source/destination filters by tag rather than by CIDR.
- **Cost attribution** &mdash; billing labels linked to tags for finance rollup.

Every one of these patterns is powerful. Together they can express governance the folder tree alone cannot (per-workload variation within a folder).

But there is a catch: **tags are only useful if downstream consumers actually bind them to resources with discipline**. A tag catalog with no bindings is bookkeeping without payoff. And every binding is one more thing to maintain when workloads spin up.

Two design decisions I had to make:

1. **Should the stack be opt-in or on by default?**
2. **Which tags belong in the reference catalog?**

## Decision

**Opt-in by default** (`enable_tags = false`) &mdash; the operator explicitly enables the stack when they are ready to commit to the binding discipline downstream.

**Reference catalog of 4 tag keys** shipped when enabled:

| Tag key | Purpose | Reference values |
|---|---|---|
| `environment` | Deployment environment | `prod`, `preprod`, `dev` |
| `data-classification` | Data sensitivity | `public`, `internal`, `confidential`, `restricted` |
| `cost-center` | Cost rollup | free-form (populate per customer) |
| `owner` | Owning team / BU | free-form |

Each of `cost-center` and `owner` has its own enable switch (`enable_cost_center_tag`, `enable_owner_tag`, default `true` when the stack is enabled).

Additional tags via `custom_tag_keys` for use-case-specific needs (compliance scope, application, etc.).

Every tag key ships with `purpose = "GCE_FIREWALL"` so the tag is usable for hierarchical firewall policies. This does not force firewall use &mdash; the tag also works for IAM Conditions, org policies, and cost attribution.

## Rationale

### Why opt-in

Enabling the stack is cheap (creates 4-6 tag keys and ~7 tag values). The cost is what happens after: every project the customer creates now needs a tagging decision. Every LZ needs to propagate tag bindings. Cost attribution requires enabling detailed billing export + BigQuery. IAM Conditions referencing tags require every human granting access to think about tags.

If the customer is not ready for that operational discipline &mdash; if there is no team owning "tagging strategy", if finance is not consuming cost-center data, if there is no security-team pull for tag-based IAM Conditions &mdash; then shipping the catalog just creates unused GCP resources.

Opt-in default respects that not every customer is ready. Customers who are ready enable the stack with one variable flip.

### Why these four tags (and not more)

Every tag I ship in the catalog needs to justify its existence with a real consumer pattern in my prior projects:

- **`environment`**: universal. Every enterprise deployment I have worked with distinguishes prod / preprod / dev at the project level. Tag surfaces the same distinction to policies, IAM, and firewall rules. Values match the portfolio's folder tree naming (`PRO/PRE/DEV` lowercased for GCP tag validation rules).
- **`data-classification`**: mandatory for any deployment under GDPR / NIS2 / most compliance regimes. The 4-tier scheme (public / internal / confidential / restricted) matches ISO 27002's information classification recommendation and is the most common corporate scheme I have seen.
- **`cost-center`**: universal for finance chargeback. Free-form values because every customer has their own finance taxonomy (departments, projects, subsidiaries). Opt-out (`enable_cost_center_tag = false`) for customers where cost attribution is handled outside GCP (billing export to enterprise system with a separate rollup).
- **`owner`**: universal for operational accountability. Free-form values (team names, BU names). Opt-out for customers with a single owner across the whole GCP org.

Tags I considered and rejected from the reference catalog:

- **`compliance-scope`** (pci / hipaa / gdpr / none): important but not universal. Belongs in `custom_tag_keys` for customers where it applies.
- **`workload-type`** (batch / online / analytics): too domain-specific.
- **`criticality`** (tier-1 / tier-2 / tier-3): overlaps with `environment` for most customers. Ship if the customer has clear operational criticality tiers distinct from env.
- **`region`**: redundant with the resource's actual region attribute. Tag adds no value.

### Why `purpose = "GCE_FIREWALL"`

Setting the purpose enables the tag to be used in hierarchical firewall policies (`google_compute_firewall_policy_rule` with `match { src_secure_tags = [...] }`). Without this purpose, the tag can be used for IAM Conditions and org policies but not for firewall rules.

Setting it does not force firewall use &mdash; the tag works for all its intended consumers. It is the maximally-capable purpose. No downside I have found to shipping with this purpose.

## Trade-offs

- **Opt-in has an activation-cost** &mdash; the customer who does want tags must know the stack exists and enable it. Mitigated by (a) this stack being enumerated in the root README stack table; (b) the tfvars example documenting when to enable.
- **Reference catalog does not fit every customer** &mdash; a customer whose `environment` scheme is `production / staging / development` (verbose) must override the reference values. Not a big deal; the variable takes an override list.
- **`purpose = "GCE_FIREWALL"` can only be set at creation** &mdash; changing it later requires recreating the tag key (destroys the value tree, breaks any binding). Discipline: set the purpose right the first time. Ship `GCE_FIREWALL` as the maximally-capable choice for all reference keys.
- **Tags are per-resource-type bindable, not universal** &mdash; not every GCP resource type supports tag binding. Projects, folders, GCE resources, GKE resources do; some others don't. Consumers must check per resource.

## Alternatives considered

**A. On-by-default with reference catalog.**
Rejected. Creates unused resources for customers not ready for tag discipline. Better to require an explicit opt-in.

**B. Ship no reference catalog &mdash; only `custom_tag_keys`.**
Rejected. The catalog is the opinion. Every customer using tags wants roughly this set; shipping it with defaults saves the operator from re-deriving the taxonomy from scratch.

**C. Ship a bigger catalog (add `compliance-scope`, `criticality`, `workload-type`).**
Rejected. Universality test: only ship tags every customer needs. Domain-specific tags belong in `custom_tag_keys`.

**D. Split reference tag keys into separate stacks (e.g. 60-tags-cost, 60-tags-governance, 60-tags-network).**
Rejected. Over-fragmentation. Tags are a single taxonomy concept; splitting them across stacks would require multiple state buckets for a small resource count. The single stack with per-key enable switches is the right granularity.

**E. `purpose` = `data_only` (allow all uses except firewall).**
Rejected. Would require operators who want firewall rules with tags to recreate the tag keys later (which destroys the value tree). Ship `GCE_FIREWALL` to keep options open.

## Controls this decision supports

Language convention: "supports controls typically found in ..." not "complies with". Precise clause IDs in [`../security/control-mapping.md`](../security/control-mapping.md).

- **NIS2** &mdash; asset management and risk categorisation areas (Art. 21). `data-classification` and `environment` tags support risk-based control application.
- **ISO/IEC 27001 &amp; 27002** &mdash; information classification (`data-classification` tag directly aligns), asset management, access control.
- **NIST CSF** &mdash; ID (Identify) function, asset management category (asset ownership, classification).
- **NIST SP 800-53** &mdash; RA (Risk Assessment) family, particularly RA-2 (security categorization).
- **CIS Google Cloud Foundation Benchmark** &mdash; asset management principles.
- **Google Cloud Architecture Framework** &mdash; governance patterns (tag-based policy, cost attribution).
- **GDPR** &mdash; when `data-classification` includes values reflecting personal-data sensitivity, supports the requirement to categorise processing (Art. 30).

## Maturity path

**Current implementation** &mdash; 4-key reference catalog opt-in, `custom_tag_keys` for extensions, `GCE_FIREWALL` purpose for max compatibility.

**Enhanced**:
- Add automated tag binding via a Cloud Run / Cloud Function trigger on project creation (auto-tag new projects based on their folder path).
- Add tag-based IAM Condition examples in `custom_org_iam_bindings` (see `50-org-iam`) demonstrating patterns for other engineers to follow.
- Add tag-based org policy conditions in `30-org-policies` (e.g. `deny_external_ip` except when `environment=sandbox`).
- Add BigQuery integration for tag-based cost attribution rollup.

**High-isolation option**:
- Add `compliance-scope` tag key with values `pci`, `hipaa`, `gdpr-strict`, `sovereign`, `none`. Bind on every project. Trigger stricter policies via IAM Conditions and org-policy conditions when compliance-scope tags are set.
- Add `criticality` tag for regulated tier-1 workloads with dedicated on-call escalation, backup frequency, and DR RPO/RTO alignment.
- Integrate tags with Assured Workloads binding for regulated tenants (Assured Workloads implicitly manages some governance labels).

Full portfolio-level roadmap in [`../security/maturity.md`](../security/maturity.md).

## References

- [`../../stacks/60-tags/README.md`](../../stacks/60-tags/README.md) &mdash; stack documentation.
- [`../architecture.md`](../architecture.md) &mdash; section on `60-tags`.
- [ADR-0009](0009-layered-segmentation-hierarchy-first.md) &mdash; tags are a mechanism for expressing Scale 1 governance decisions at Scale 3 (firewall) via `purpose = "GCE_FIREWALL"`.
- [GCP: Resource Manager tags](https://cloud.google.com/resource-manager/docs/tags/tags-overview) &mdash; canonical reference.
- [GCP: Tag-based IAM Conditions](https://cloud.google.com/iam/docs/conditions-attribute-reference#resource_tag) &mdash; downstream consumer pattern.
- [GCP: Hierarchical firewall policies with secure tags](https://cloud.google.com/firewall/docs/tags-firewalls-overview) &mdash; another downstream consumer pattern.
