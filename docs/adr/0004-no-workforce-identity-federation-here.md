<!--
File:        docs/adr/0004-no-workforce-identity-federation-here.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0004: Workforce Identity Federation is not in Tier 0 &mdash; it belongs in the identity baseline

**Status**: Accepted
**Date**: 2026-08-07
**Deciders**: Ismael Cruz
**Tags**: gcp, tier-0, tier-1, identity, wif, blast-radius

## Context

Workforce Identity Federation (WIF) is often bundled into "org hierarchy" material because its name suggests org-scope concerns and because the AWS sibling has IAM Identity Center in `aws-org-hierarchy`'s `60-identity-center` stack. Two forces pull WIF toward Tier 0:

1. **Naming**: WIF has "Workforce" and "Federation" &mdash; both feel platform-wide.
2. **AWS parity**: Identity Center is provisioned by `aws-org-hierarchy`. Symmetry argues for the same in GCP.

Two counter-forces pull WIF toward Tier 1 (`gcp-identity-baseline`):

1. **Resource scope**: `google_iam_workforce_pool` and `google_iam_workforce_pool_provider` are project-scoped resources (they live inside a specific project &mdash; typically `piam`). They do **not** need org-scope permissions to create; they need `roles/iam.workforcePoolAdmin` at the project level.
2. **Coupling to identity discipline**: WIF is intimately coupled to Google Groups (`google_cloud_identity_group`), custom roles (`google_organization_iam_custom_role`), IAM patterns / templates, and break-glass procedures. These are **identity concerns**, not hierarchy concerns.

The AWS analogy is also weaker than it looks: Identity Center is different from WIF in scope and API. IdC is inherently org-scoped (`aws_ssoadmin_instance` is an org-level resource); WIF is not.

## Decision

**Workforce Identity Federation lives in `gcp-identity-baseline` (Tier 1).** Tier 0 creates the `piam` project (in stack `20-projects`) and stops there. WIF pools, providers, group provisioning, custom roles, and IAM patterns are all inside identity-baseline, deployed into `piam`.

Tier 0 does own two thin things adjacent to identity:

- **Essential contacts** at the Org scope (stack `00-org-baseline`) &mdash; security / billing / technical notification recipients. Genuinely org-scope.
- **Org-scope IAM bindings** for Org Admin / Project Creator / Billing Admin / break-glass user (stack `50-org-iam`, planned v0.3.0). These are the minimum privileged principals that must exist for Tier 0 itself to function.

Everything else identity-related is in Tier 1.

## Consequences

**Positive**:

- Identity-baseline runs with project-scope permissions on `piam` plus optional org-scope for custom roles &mdash; not with the sweeping org-scope rights Tier 0 SA holds.
- Changing WIF providers, adding a new IdP, rotating a group's members &mdash; none of these need Tier 0 SA. All happen at Tier 1 velocity.
- Blast radius: a broken WIF change breaks federation for future logins; it does not break the hierarchy, the folder tree, or the platform projects.
- Symmetry with the tier taxonomy is preserved: Tier 0 = containers, Tier 1 = services inside containers. WIF is a service, not a container.

**Negative**:

- Cross-cloud reviewers coming from AWS may expect WIF in Tier 0 by analogy. Documented explicitly in this ADR + [`../architecture.md`](../architecture.md) to pre-empt the confusion.
- Bootstrapping a new customer means WIF is only available after both Tier 0 (creates `piam`) and Tier 1 identity-baseline (creates the pool) are applied. Two-step; acceptable.

**Neutral**:

- Consumers of WIF (typically CI pipelines federating in) do not care which tier provisioned the pool. They get the pool ID from `gcp-identity-baseline`'s remote state and configure their OIDC provider once.

## Alternatives considered

**A. Ship WIF in Tier 0's `50-org-iam` stack alongside org-scope IAM bindings.**
Rejected: bundles project-scope resources with org-scope resources in the same stack. State-level coupling for no operational benefit. Also drags Tier 0 SA into holding `roles/iam.workforcePoolAdmin` on `piam` &mdash; unnecessary.

**B. Ship WIF in its own dedicated Tier 0 stack (e.g. `70-workforce-identity-federation`).**
Rejected: still Tier 0 in name and privilege, even if isolated by stack. The privilege model does not change. Better to move it entirely to Tier 1 where the privilege model matches.

**C. Ship WIF in Tier 0 for "convenience of setup" (customer runs Tier 0 and immediately has federation).**
Rejected: convenience over correctness. Customers running Tier 0 first also apply Tier 1 identity-baseline immediately after &mdash; the ergonomic gain is nil. And Tier 1 identity-baseline lands sooner (see portfolio roadmap) so the artificial split of WIF-in-Tier-0 would exist for a matter of weeks anyway.

## References

- [`../architecture.md`](../architecture.md) &mdash; section "Why Workforce Identity Federation is not here".
- [GCP: Workforce Identity Federation](https://cloud.google.com/iam/docs/workforce-identity-federation) &mdash; canonical reference; `google_iam_workforce_pool` is project-scoped.
- Future Tier 1 repo `baseline-projects/gcp-identity-baseline/` &mdash; will own WIF pools, providers, groups, custom roles.
- Sibling repo [`../../../aws-org-hierarchy/README.md`](../../../aws-org-hierarchy/README.md) &mdash; the AWS Identity Center placement this ADR deliberately does not mirror.
