<!--
File:        docs/pending-corrections.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Punch list of corrections identified during disciplined
             architectural review. Items are either real bugs (✕, code
             disagrees with docs) or research (△, decisions requiring
             GCP/framework verification before implementing a fix). Each
             fix lands in a future code release (not a doc-only patch)
             once the accumulated review across sections 30-60 is
             complete.
-->

# Pending corrections

This file tracks findings from the disciplined architectural review of `gcp-org-hierarchy` that are **not yet fixed**. Two categories:

- **✕ Bug** &mdash; the code does something different from what the docs / ADRs say. Requires a code change.
- **△ Research** &mdash; a decision that requires verification against current GCP / framework documentation before implementing the fix. May change the shape of the fix once resolved.

Portfolio-quality signal: a rigorous review of shipped code always finds items. Tracking them openly is more honest than pretending the release is perfect. The correction cycle happens as a batch after the review of all 7 stacks is complete, so the code changes can be reasoned about coherently rather than as one-off patches.

---

## From section 30 review (org-policies)

### ✕ Bug: `dry_run_spec` not implemented in `google_org_policy_policy`

**Where**: [`stacks/30-org-policies/main.tf`](../stacks/30-org-policies/main.tf) &mdash; both `google_org_policy_policy.catalog` and `google_org_policy_policy.custom` blocks.

**What the docs say**: [ADR-0011](adr/0011-curated-org-policy-catalog.md), the stack README, and the variable defaults all promise **dry-run-first**: `default_dry_run = true`, per-policy `enforce_overrides` map, `effective_dry_run` local computed per policy.

**What the code does**: the effective `dry_run` value computed in [`locals.tf`](../stacks/30-org-policies/locals.tf) (`local.enabled_catalog[k].dry_run`) is **never consumed** by the resource. The resource unconditionally uses the `spec { rules { ... } }` block, which in GCP's Org Policy v2 API means the LIVE policy. The `dryRunSpec` alternative is not used at all.

**Consequence**: enabling a policy in this stack applies it as LIVE / enforced, regardless of the `default_dry_run` and `enforce_overrides` settings. The dry-run-first workflow documented in ADR-0011 is not what the code delivers.

**Fix direction** (pending research in the next item):
- Use `dry_run_spec { rules { ... } }` block when `effective_dry_run = true` for a given catalog entry.
- Use `spec { rules { ... } }` block when `effective_dry_run = false` (enforce).
- Same treatment for the `custom_org_policies` resource block (the `dry_run` field on the custom object is currently unused).

**Blocker**: not every constraint supports `dry_run_spec`. See the △ research item below.

### ✕ Bug: `custom_org_policies.dry_run` variable field is declared but unused

**Where**: [`stacks/30-org-policies/variables.tf`](../stacks/30-org-policies/variables.tf) declares `dry_run = optional(bool, true)` inside the `custom_org_policies` object type, but [`main.tf`](../stacks/30-org-policies/main.tf) `google_org_policy_policy.custom` never reads it.

**Consequence**: operators supplying `dry_run = true` on a custom policy get no dry-run behaviour. Silently mis-honoured input is worse than a rejected input.

**Fix direction**: same as the catalog fix &mdash; branch on the value into `dry_run_spec` vs `spec`. Alternatively, if a constraint used in `custom_org_policies` does not support dry-run, plan-time precondition to reject the `dry_run = true` value with a clear error.

### △ Research: legacy vs managed constraints and dry-run availability

**Where**: applies to the whole catalog design in [`stacks/30-org-policies/`](../stacks/30-org-policies/) plus ADR-0011.

**What needs verification against current GCP 2026 docs**:

- GCP distinguishes **managed constraints** (modern, better Policy Intelligence integration, richer dry-run support) from **legacy managed constraints** and **custom constraints**.
- The 8 constraints currently in the catalog (`iam.disableServiceAccountKeyCreation`, `compute.requireOsLogin`, `compute.vmExternalIpAccess`, `storage.publicAccessPrevention`, `sql.restrictPublicIp`, `iam.allowedPolicyMemberDomains`, `compute.trustedImageProjects`, `gcp.resourceLocations`) belong to the legacy-managed model.
- Google is progressively introducing managed equivalents for some legacy constraints. Managed constraints are the recommended primitive for new deployments where an equivalent exists.
- **Dry-run availability**: Google documents restrictions on which constraints can be evaluated in dry-run mode. Not every legacy constraint supports it directly.

**Decision needed before the ✕ bug fixes above**:
1. For each of the 8 constraints, verify current GCP status: legacy? Managed equivalent available? Dry-run supported?
2. Where a managed equivalent exists, decide whether to migrate the catalog entry to the managed constraint (better tooling, cleaner dry-run) or stay on legacy for backwards compatibility.
3. Where dry-run is not supported for a specific constraint, decide whether to (a) drop dry-run for that entry and document the exception, (b) skip enforcement entirely until manual verification, or (c) migrate to a managed equivalent that supports it.

**Not a rewrite of the 8 security decisions** &mdash; the catalog choices stand. This is about which GCP primitive materialises each choice.

---

## Convention for using this file

- Each item lands here when a review section identifies it and stays here until a code release fixes it.
- Fixes come in code releases (not doc-only patches), grouped by theme where possible (e.g. a `v0.5.0` might address all `stacks/30-org-policies/` bugs at once).
- When an item is fixed, remove it from this file in the same commit that applies the fix. The commit message references the item.
- This file is portfolio-honest: it says "review found these; fix cycle is upcoming". It is not a bug tracker for issues found during real deployment (those go through GitHub Issues on the repo).
