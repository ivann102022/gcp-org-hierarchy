<!--
File:        docs/adr/0007-content-rule-for-org-baseline.md
Author:      Ismael Cruz
Version:     0.1.0
-->

# ADR-0007: Content rule for stack `00-org-baseline` &mdash; org-scope + fundacional + not-a-discipline

**Status**: Accepted
**Date**: 2026-08-07
**Deciders**: Ismael Cruz
**Tags**: gcp, tier-0, content-rule, anchor-baseline, blast-radius

## Context

Stack `00-org-baseline` is the anchor of Tier 0. Its role is dual: **anchor** (publish canonical Org contract facts) + **baseline** (provision the minimum org-scope elements administered from apply #1).

The stack is intentionally minimal today &mdash; a data-source lookup plus optional `google_essential_contacts_contact`. Which raises the question every operator asks eventually: "What *else* should live here?"

Without a clear content rule, two failure modes appear over time:

1. **The catch-all creep**: every new org-scope resource that doesn't obviously fit elsewhere lands in `00-org-baseline` "because it's fundacional". Eventually the stack absorbs org sinks, org IAM, org policies, tags &mdash; erasing the reason `30`/`40`/`50`/`60` exist.

2. **The under-scoping**: operators unsure whether something belongs here just skip it, leaving org-scope concerns un-managed. Contracts stay half-published.

Both failure modes stem from the same absence: no explicit test the operator can apply to a candidate.

## Decision

A candidate belongs in stack `00-org-baseline` **only if all three criteria hold**:

| # | Criterion | Test |
|---|---|---|
| 1 | **Org-scope** | Its natural scope is the Organization, not a folder or project. `google_essential_contacts_contact` with `parent = "organizations/..."` passes; the same resource with `parent = "projects/..."` fails. |
| 2 | **Fundacional** | Established at apply #1 (or immediately after the anchor lookup), not at apply #N when the portfolio has matured. IAM Org Admin binding passes on this criterion; a per-LZ dashboard fails. |
| 3 | **Not a discipline** | Does not fall cleanly under Policies (30), Logging (40), IAM (50), or Tags (60). If it does, it goes to the dedicated stack &mdash; even if it's org-scope and fundacional. |

Criterion 3 is the guardrail. Criteria 1 and 2 alone would let almost anything qualify. Criterion 3 forces the question "which discipline owns this?" and refuses membership to any candidate a discipline claims.

## Worked examples

| Candidate | Org-scope | Fundacional | Not a discipline | Belongs in |
|---|---|---|---|---|
| `google_essential_contacts_contact` at Org scope | ✓ | ✓ | ✓ (not policy, not logging, not IAM, not tag) | **`00-org-baseline`** |
| Hypothetical `google_organization_settings` (metadata without a discipline home) | ✓ | ✓ | ✓ | **`00-org-baseline`** |
| `google_logging_organization_sink` | ✓ | ✓ | ✗ &mdash; **Logging discipline** | `40-org-logging` |
| `google_org_policy_policy` for `iam.disableServiceAccountKeyCreation` | ✓ | ✓ | ✗ &mdash; **Policies discipline** | `30-org-policies` |
| `google_organization_iam_member` for Org Admin | ✓ | ✓ | ✗ &mdash; **IAM discipline** | `50-org-iam` |
| `google_tags_tag_key` at Org scope | ✓ | ✓ | ✗ &mdash; **Tags discipline** | `60-tags` |
| Cloud Asset Inventory export config at Org scope | ✓ | ✓ | ambiguous &mdash; audit/inventory is close to Logging but not exactly | Decide at implementation time; default to `40-org-logging` if the destination is a log bucket, otherwise a new stack. |
| `google_dns_managed_zone` (public zone at Org scope) | ✗ (project-scope) | &mdash; | &mdash; | Tier 1 `gcp-dns-baseline` (inside `pdns`) |

## Consequences

**Positive**:

- **Predictable placement**. A new operator with a candidate resource has a mechanical test to apply. No debate, no waiting for a review.
- **Prevents catch-all creep**. Criterion 3 forces every candidate to name a discipline. If the candidate names one, it goes there. Membership in `00-org-baseline` requires actively arguing "no discipline claims this", which is a rare and legitimate case.
- **Prevents under-scoping**. Once the test says "yes", the operator knows the resource belongs and can proceed confidently.
- **Documentable**. The rule fits in a 3-row table &mdash; readable in a PR description or a design review.

**Negative**:

- **Edge cases exist**. Cloud Asset Inventory (audit/inventory) is genuinely on the boundary between Logging (destination is a log bucket) and its own "discipline". The rule surfaces the ambiguity rather than resolving it &mdash; the operator has to make a call. Documented as a known limitation.
- **Requires the disciplines to exist**. Criterion 3 references stacks `30`/`40`/`50`/`60`, some of which are still planned. Until they ship, a candidate that "belongs" in `40-org-logging` has no home. Interim workaround: park such candidates in `00-org-baseline` with a `// TODO: move to 40-org-logging when it ships` note.

**Neutral**:

- **The rule applies to future portfolio siblings too** &mdash; `aws-org-hierarchy/00-org-baseline` and the future `azure-mg-hierarchy/00-mg-baseline` should follow the same rule (org-scope + fundacional + not-a-discipline), adapted to each CSP's stack numbering.

## Alternatives considered

**A. No rule &mdash; operators decide case by case.**
Rejected: leads to both failure modes above. Enough repos in the portfolio grow to the point where at least one turns into a catch-all; other repos then imitate.

**B. Two-criterion rule: org-scope + fundacional (drop "not a discipline").**
Rejected: opens the catch-all door. Every org sink and every org policy is org-scope + fundacional &mdash; they'd all cluster in `00-org-baseline` on first review.

**C. Whitelist-only: enumerate the resources allowed in `00-org-baseline` and refuse everything else.**
Rejected: too rigid. New GCP APIs emerge that fit the pattern naturally; a whitelist would need constant updates. The three-criterion rule is stable across API changes.

**D. Move essential contacts out of `00-org-baseline` and into a dedicated discipline stack (e.g. new `70-notifications`).**
Rejected: essential contacts genuinely do not constitute a discipline. Making a dedicated stack for a single resource type inflates the taxonomy without payback. If a critical mass of notification-related resources emerges later (contact groups, notification channels at Org scope, ...), reconsider.

## References

- [../../stacks/00-org-baseline/README.md](../../stacks/00-org-baseline/README.md) &mdash; the anchor + baseline pattern.
- [../architecture.md](../architecture.md) &mdash; section "Stack `00-org-baseline`: the anchor + baseline pattern".
- [ADR-0001](0001-two-modes-only-existing-and-create.md) &mdash; the `create` mode of `00-org-baseline` refers to essential contacts (and future baseline additions), never to the Organization itself.
