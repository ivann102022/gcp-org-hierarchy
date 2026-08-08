<!--
File:        docs/adr/0005-folder-per-platform-project.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0005: One folder per platform project under `Platform` (1:1)

**Status**: Accepted
**Date**: 2026-08-07
**Deciders**: Ismael Cruz
**Tags**: gcp, tier-0, folders, iam-scope, org-policies

## Context

Tier 0 provisions six reference platform projects (`plogs`, `pmgm`, `piam`, `pdns`, `pingress`, `sandbox`). At v0.2.0 design time three shapes for their folder placement presented themselves:

1. **Flat**: every platform project sits directly under `Platform`. Zero sub-folders.
2. **Discipline-grouped**: sub-folders under `Platform` group projects by function &mdash; e.g. `Identity` (`piam`), `Management` (`plogs`, `pmgm`), `Connectivity` (`pdns`, `pingress`).
3. **1:1 folder per project**: each platform project lives in its own dedicated sub-folder &mdash; `Logs` for `plogs`, `Management` for `pmgm`, `IAM` for `piam`, `DNS` for `pdns`, `Ingress` for `pingress`.

Option 1 (flat) was v0.1.0's shape. It works but limits IAM/policy granularity: any binding on `Platform` applies to every platform project.

Option 2 (discipline-grouped) reduces the folder count and clusters "related" projects. But the semantics of "related" are subjective &mdash; is `piam` closer to `pmgm` (both management/security) or to `pingress` (both consumed by external actors)? The grouping is a modelling choice that other teams will second-guess.

Option 3 (1:1) matches the number of folders to the number of projects, making IAM and org-policy scoping directly aligned with the project boundary.

## Decision

**One folder per platform project under `Platform`.** Reference set for the default six projects:

| Folder (child of `Platform`) | Home of platform project |
|---|---|
| `Logs` | `plogs` |
| `Management` | `pmgm` |
| `IAM` | `piam` |
| `DNS` | `pdns` |
| `Ingress` | `pingress` |

`sandbox` lives under the `Sandbox` root (not under `Platform`) &mdash; it's a distinct namespace, not a platform service.

Implementation: `var.reference_platform_children` on `10-folders` defaults to `["Logs", "Management", "IAM", "DNS", "Ingress"]`; `var.platform_project_home_folder` on `20-projects` defaults to the mapping above.

## Consequences

**Positive**:

- **Granular IAM scoping**. `roles/dns.admin` on the `DNS` folder applies **only** to `pdns` &mdash; the operator responsible for DNS gets exactly the scope they need, nothing more. Under discipline-grouped (Option 2), granting DNS admin on `Connectivity` would also grant it (incorrectly) on `pingress`, forcing project-scope bindings and losing the folder-inheritance benefit.
- **Per-folder org policies**. A policy like `constraints/compute.vmExternalIpAccess` (deny all external IPs) can be attached at the `DNS` folder without leaking to `Ingress` (which legitimately needs external IPs). Under discipline-grouped, the policy would either misapply or require exceptions.
- **Clean audit surfaces**. `gcloud asset search-all-resources --scope=folders/<Logs>` returns exactly the `plogs` project's resources. Zero ambiguity about which project a query targets.
- **Growth path**: adding a `pmonitoring` project separate from `pmgm` in the future creates a new sibling folder `Monitoring` under `Platform` &mdash; no rename of existing folders, no re-scoping of existing IAM.
- **Documentation clarity**: the reader sees "one folder per project" as a mechanical rule; no need to understand why `piam` was grouped with X but not Y.

**Negative**:

- **More folders**: 5 sub-folders under `Platform` (default) instead of 0 (flat) or 3 (discipline-grouped). Insignificant &mdash; GCP supports thousands of folders per Org; the extra tree depth costs nothing operationally.
- **The reader must know the mapping**. Someone new to the repo has to learn that `plogs` lives in `Logs` (not just intuit it from a discipline label). Mitigated by the mapping being 1:1 and lexicographically obvious (`plogs` &rarr; `Logs`).

**Neutral**:

- **`Sandbox` intentionally stays a root**, not a `Platform` child. Sandbox is a distinct namespace (different lifecycle: ephemeral, looser IAM, opt-in policies) &mdash; forcing it under `Platform` would blur the distinction. This ADR does not change that.

## Alternatives considered

**A. Flat &mdash; all platform projects directly under `Platform` (v0.1.0 shape).**
Rejected: loses per-project IAM/policy granularity. Every operational grant fan-outs to every platform project. Works for a demo; breaks for real deployments where the operator wants DNS admin scoped to just DNS.

**B. Discipline-grouped &mdash; `Identity`, `Management`, `Connectivity` (v0.2.0 WIP, superseded by this ADR).**
Rejected: subjective grouping ("is `piam` closer to `pmgm` or `pingress`?") introduces a modelling layer that other operators re-open. Also fails the IAM scoping test: `roles/dns.admin` on `Connectivity` would incorrectly apply to `pingress`.

**C. 1:1 folder per project, but scoped only to a subset (e.g. only for `plogs` and `pdns`, others flat).**
Rejected: the split is arbitrary &mdash; why those two? Once we accept the 1:1 pattern, applying it uniformly is cleaner than a subset with special cases.

**D. Nested by discipline THEN by project (`Platform/Connectivity/DNS`, `Platform/Connectivity/Ingress`).**
Rejected: extra depth (4 levels: Org &rarr; Platform &rarr; Connectivity &rarr; DNS &rarr; project) without payback. Discipline layer would just be a naming convention, not adding IAM or policy benefit over 1:1 direct children.

## References

- [../architecture.md](../architecture.md) &mdash; the v0.2.0 folder tree.
- [../../stacks/10-folders/README.md](../../stacks/10-folders/README.md) &mdash; `reference_platform_children` variable.
- [../../stacks/20-projects/README.md](../../stacks/20-projects/README.md) &mdash; `platform_project_home_folder` mapping.
- [ADR-0002](0002-platform-projects-here-not-in-lz.md) &mdash; sibling decision: platform projects are owned by Tier 0.
- [ADR-0006](0006-landing-zones-hostprj-serviceprj-env-split.md) &mdash; sibling decision: the LandingZones sub-tree shape.
