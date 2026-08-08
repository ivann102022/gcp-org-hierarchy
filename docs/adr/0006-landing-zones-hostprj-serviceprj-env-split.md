<!--
File:        docs/adr/0006-landing-zones-hostprj-serviceprj-env-split.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0006: `LandingZones` sub-tree — `HUB` flat + `HostPrj` / `ServicePrj` with environment sub-folders

**Status**: Accepted
**Date**: 2026-08-07
**Deciders**: Ismael Cruz
**Tags**: gcp, tier-0, folders, landing-zones, shared-vpc, environments

## Context

The `LandingZones` root folder is where Tier 2 LZs land their tenant projects. At v0.2.0 design time, three questions came together:

1. **How does the LZ split into projects?** GCP's Shared VPC pattern has two roles: **host projects** hold the VPCs (network policy, subnets, peerings); **service projects** attach to a host to consume its VPCs. That's the recommended pattern &mdash; used by both shipped GCP LZs (`gcp-lz-fortinet-multiproject`, `gcp-lz-ncc-bgp-appliance`).

2. **Do we split by environment?** Almost every enterprise deployment separates `PRO` / `PRE` / `DEV` at the project level (per-env IAM, per-env budgets, per-env change windows). The two shipped LZs already do this (`pnet-pro`, `pnet-pre`, `pnet-dev`).

3. **What about the HUB?** The hub network (single FortiGate perimeter appliance, single Internet egress, single VPN termination) is shared across environments by design &mdash; you don't want three FortiGates fighting for the same public IP block.

Combining (1) and (2) yields a 2&#x00D7;3 = 6-cell grid: {Host, Service} &#x00D7; {PRO, PRE, DEV}. Combining with (3) adds one more cell for HUB. That's 7 leaves under `LandingZones`.

How to shape the folder tree above those leaves matters because it drives IAM inheritance:

- **Flat** (all 7 under `LandingZones`): no environment inheritance; per-env IAM has to be per-project.
- **Env-first** (`LandingZones/PRO/HostPrj`, `LandingZones/PRO/ServicePrj`, `LandingZones/PRO/HUB`?): env at level 2, role at level 3. Awkward for HUB (which isn't per-env).
- **Role-first** (`LandingZones/HostPrj/PRO`, `LandingZones/HostPrj/PRE`, ..., `LandingZones/HUB`): role at level 2, env at level 3. HUB fits naturally as a role that happens to be flat.

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

## Composite keys

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

## Consequences

**Positive**:

- **Env-scope IAM works naturally**. `roles/compute.networkAdmin` on `LandingZones/HostPrj/PRO` grants network admin only on the PRO host project &mdash; the split between host and service is preserved (service-project team doesn't accidentally get network-admin on the host).
- **Role-scope IAM works too**. `roles/compute.networkAdmin` on `LandingZones/HostPrj` grants across all envs of the host role &mdash; useful for network team members who own PRO+PRE+DEV.
- **HUB fits cleanly as a "role that isn't env-split"** &mdash; the `has_environments = false` flag on that entry is the mechanism. Same variable, one bool flip.
- **Aligns with the GCP LZ codebase**. Both shipped LZs already use `pnet-pro`/`pnet-pre`/`pnet-dev` and `srv-pro`/`srv-pre`/`srv-dev`. Zero rename ripple.
- **Depth stays reasonable**: max depth for reference tree is 3 (Org &rarr; LandingZones &rarr; HostPrj &rarr; PRO). Well under GCP's 10-deep limit.

**Negative**:

- **Terraform key vs display name distinction is a small extra concept for the reader**. Documented explicitly in the `10-folders` README and this ADR. If the reader forgets and uses `folder_ids["PRO"]`, they get `null` &mdash; fails fast at plan time.
- **Env customisation is per-env-list, not per-role**. If a customer wants `HostPrj` to have `PRO/PRE/DEV` but `ServicePrj` to have only `PRO/DEV`, they must either override `reference_landing_zone_environments` (which applies to both) or use `custom_folders`. Not painful, but worth noting.

**Neutral**:

- **HUB is a folder with a single project**. Feels wasteful compared to putting `pnet-hub` directly under `LandingZones`. But the folder gives HUB the same IAM/policy attach point as HostPrj/ServicePrj &mdash; consistent treatment across the three roles.
- **Sandbox is deliberately outside this sub-tree**. Sandbox is a distinct root, not a landing zone, per [ADR-0005](0005-folder-per-platform-project.md).

## Alternatives considered

**A. Flat &mdash; all 7 leaves directly under `LandingZones`.**
Rejected: loses env-scope IAM inheritance. Per-env grants would need per-project bindings, defeating folder inheritance.

**B. Env-first &mdash; `LandingZones/PRO/{HostPrj, ServicePrj}`, `LandingZones/PRE/...`, `LandingZones/HUB`.**
Rejected: HUB does not fit &mdash; it sits at the same level as env roots but is not an env. Also: env-first fights the natural grouping (`HostPrj` and `ServicePrj` are related concerns; splitting them across the env axis at level 2 forces extra reasoning to see the pattern).

**C. Role-first without composite keys &mdash; nested map with recursive resource block.**
Rejected: Terraform recursive folder module was tried in earlier work; the added complexity of nested-map propagation outweighs the string-concat savings. Composite keys in a flat map are boring and correct.

**D. Ship without `HUB` in the reference tree &mdash; leave it as `custom_folders` for LZs that need it.**
Rejected: every LZ in the portfolio needs a HUB. Making it a default is the right call; LZs that don't need it override with `has_environments = false` and skip the HUB project creation.

## References

- [../architecture.md](../architecture.md) &mdash; the v0.2.0 folder tree.
- [../../stacks/10-folders/README.md](../../stacks/10-folders/README.md) &mdash; composite keys convention, `reference_landing_zone_children` and `reference_landing_zone_environments` variables.
- [ADR-0005](0005-folder-per-platform-project.md) &mdash; sibling decision: the `Platform` sub-tree.
- [ADR-0008](0008-ingress-bypasses-perimeter-appliance.md) &mdash; why the HUB (with its FortiGate appliance) isn't in the path for public ingress.
- [GCP Shared VPC overview](https://cloud.google.com/vpc/docs/shared-vpc) &mdash; the host/service pattern this sub-tree encodes.
