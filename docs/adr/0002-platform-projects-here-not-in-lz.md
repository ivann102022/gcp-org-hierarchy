<!--
File:        docs/adr/0002-platform-projects-here-not-in-lz.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0002: Platform projects (`plogs` / `pmgm` / ...) are created here, not by each landing zone

**Status**: Accepted
**Date**: 2026-08-07
**Deciders**: Ismael Cruz
**Tags**: gcp, tier-0, tier-1, tier-2, project-factory, ownership

## Context

Six projects are consumed by every GCP tier as if they were platform-level concerns:

- `plogs` &mdash; centralized logs, org-sink destination.
- `pmgm` &mdash; KMS central + management.
- `piam` &mdash; identity foundation.
- `pdns` &mdash; Cloud DNS host.
- `pingress` &mdash; shared ingress baseline.
- `sandbox` &mdash; sandbox.

Historically, the GCP LZ (`gcp-lz-fortinet-multiproject`) shipped a `create_projects = true` mode inside its `00-network-core` stack that provisioned these projects. That worked when there was one LZ. It stops working when there is a second LZ: the two LZs either try to own the same project IDs (conflict on `terraform apply`) or drift into different naming (breaks the "one platform project set per Org" invariant that baselines assume).

The concrete symptom, verified in the current portfolio: both `gcp-lz-fortinet-multiproject` and `gcp-lz-ncc-bgp-appliance` accept `create_projects = true` **but with independent inputs** &mdash; nothing prevents one LZ from naming the log project `gcp0-prj-emp-plogs-01` and the other from naming it `gcp0-prj-emp-logs-central-01`. Once that drift happens, the future observability baseline has no single project to deploy into.

## Decision

**Tier 0 (`gcp-org-hierarchy`, stack `20-projects`) is the sole owner of the platform project set.** It provisions the six reference projects with canonical names composed from portfolio-wide global variables (`org_prefix`, `company`, `division`, `control`).

The LZ's `create_projects = true` mode is retained as a **fallback** for greenfield demo deployments where no Tier 0 is being run &mdash; but its documentation explicitly recommends switching to `create_projects = false` + `existing_project_ids = data.terraform_remote_state.org.outputs.platform_project_ids` as soon as a second LZ or the first baseline is introduced.

## Consequences

**Positive**:

- **Tier 0 owns containers; Tier 1 owns capabilities inside those containers.** The clean phrase for the split. Tier 0 creates `plogs`, `pmgm`, `piam`, `pdns`, `pingress` (the containers); Tier 1 baselines populate them with capabilities (log buckets + exports + monitoring; WIF pools + custom roles; DNS zones + forwarding; SCC + KMS + Secret Manager). Ownership and privilege scope match the concern: Tier 0 SA holds org-scope; Tier 1 SAs hold project-scope only. See also [ADR-0003](0003-org-sink-in-tier0-not-obs-baseline.md), [ADR-0004](0004-no-workforce-identity-federation-here.md) for the same principle applied to specific resource types.
- Every LZ, every baseline consumes the same `platform_project_ids` map from Tier 0's remote state. Zero drift by construction.
- Platform project lifecycle (creation, movement between folders, `deletion_protection`) is governed by one repo. Blast radius of an accidental change is bounded.
- Naming defaults align across the portfolio automatically &mdash; a customer that runs Tier 0 with defaults and any GCP LZ with defaults gets project IDs that match without operator intervention.

**Negative**:

- Consumers that want to run a single LZ standalone (without deploying Tier 0) must still use the `create_projects = true` fallback and later migrate state if Tier 0 is introduced. `terraform state mv` operation is documented but is manual.
- Introduces a hard dependency from LZ apply to Tier 0 apply: consumers must apply Tier 0 first, or provision `existing_project_ids` externally. The LZ README documents this explicitly.

**Neutral**:

- Aligns with Google Cloud Foundation Fabric's `1-resman` + `2-networking` split, which also separates project provisioning from network provisioning.

## Alternatives considered

**A. Leave project creation in each LZ (`create_projects = true` per LZ).**
Rejected: proven to drift the moment a second LZ appears (see Context). Sustainable only for the single-LZ case, which is not the portfolio's target scenario.

**B. Create a dedicated `gcp-project-factory` repo separate from `gcp-org-hierarchy`.**
Rejected: over-fragmentation. The project factory is intimately coupled to the folder tree it deploys into (each project references a folder ID). Splitting them would introduce a Tier 0.5 with a tiny contract and add an extra remote-state hop for every consumer. Keep them together as the "hierarchy repo" and let the natural cohesion of "folders + projects" guide the boundary.

**C. Move platform projects to the individual baselines (`gcp-observability-baseline` creates `plogs`, `gcp-dns-baseline` creates `pdns`, ...).**
Rejected: each baseline would need `roles/resourcemanager.projectCreator` at the folder level, which is a Tier 0 privilege. Baselines are supposed to run with project-scope permissions only. Also: creates a chicken-and-egg between baselines (which one creates `pmgm` if two baselines need KMS?).

## Controls this decision supports

Language convention: "supports controls typically found in..." not "complies with". Precise clause IDs live in [`../security/control-mapping.md`](../security/control-mapping.md).

- **ISO/IEC 27001 &amp; 27002** &mdash; asset management and change management areas (single point of authority for platform project provisioning avoids drift).
- **NIST CSF** &mdash; ID (Identify) function, asset management category.
- **CIS Google Cloud Foundation Benchmark** &mdash; project management principles.
- **Google Cloud Architecture Framework** &mdash; foundation pillar, particularly the pattern of a foundational Terraform layer that owns cross-tier resources.

## References

- [`../architecture.md`](../architecture.md) &mdash; section "Why platform projects live here, not in each LZ".
- [`../contract.md`](../contract.md) &mdash; `platform_project_ids` output spec.
- [`../../../../shared-modules/terraform-gcp-modules/modules/projects/README.md`](../../../../shared-modules/terraform-gcp-modules/modules/projects/README.md) &mdash; the module this stack consumes.
- Sibling LZ [`../../../../landing-zones/gcp-lz-fortinet-multiproject/stacks/00-network-core/terraform.tfvars.example`](../../../../landing-zones/gcp-lz-fortinet-multiproject/stacks/00-network-core/terraform.tfvars.example) &mdash; the `create_projects = true` fallback path.
- [ADR-0005](0005-folder-per-platform-project.md), [ADR-0009](0009-layered-segmentation-hierarchy-first.md) &mdash; how the platform projects are placed in the segmentation model.
