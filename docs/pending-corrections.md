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

## From section 40 review (org-logging)

### ✕ Bug: `unique_writer_identity` claimed in docs, not explicit in code

**Where**: [`stacks/40-org-logging/README.md`](../stacks/40-org-logging/README.md) previously claimed the resource sets `unique_writer_identity = true`. [`stacks/40-org-logging/main.tf`](../stacks/40-org-logging/main.tf) does not set the attribute; a comment above the resource block mentions the intent but the resource itself does not include the argument. The README has been softened in v0.4.10 to remove the explicit claim and point at this correction item.

**Why it matters**:
- Documentation asserted a behaviour the code did not explicitly guarantee.
- The Terraform provider default for `google_logging_organization_sink.unique_writer_identity` may change between provider majors; relying on the default without pinning is fragile for a portfolio artifact.
- Current Cloud Logging behaviour has evolved &mdash; since 2023, GCP typically uses a shared logging service account per parent resource for sinks (rather than minting a unique SA per sink), which affects the correct value to configure explicitly.

**Fix direction**:
1. Verify current provider behaviour for `google_logging_organization_sink.unique_writer_identity` (default value, deprecation status, GCP-side behaviour).
2. Decide explicitly: unique-per-sink SA (audit clarity per sink) vs shared-per-parent SA (aligned with current GCP default). Document the choice in ADR-0012.
3. Set the attribute explicitly in `main.tf` to match the decision, so the behaviour is not implicit / provider-default.
4. Re-align README with the code once the attribute is explicit.

Not blocking normal operation &mdash; the sink works with the provider default. But the doc/code divergence is a real correctness issue.

## From section 50 review (org-iam)

### ~~✕ Bug: `roles/billing.admin` bound at Organization scope~~ &mdash; FIXED in v0.5.0

Removed from stack 50 entirely. Reasoning: `roles/billing.admin` has lowest-level grantable resource = Billing Account (not Organization). The user's decision during the review was to remove billing IAM from this stack until a concrete requirement drives adding it back (via one of the two future paths: `roles/billing.creator` at Org scope for account creation, or `google_billing_account_iam_member` at Billing Account scope for existing-account admin, likely in a dedicated `55-billing-iam` stack).

Original detail preserved below for history:

### ✕ Bug: `roles/billing.admin` bound at Organization scope (historical, fixed)

**Where**: [`stacks/50-org-iam/locals.tf`](../stacks/50-org-iam/locals.tf) &mdash; `curated_role_members` map includes `"roles/billing.admin" = var.billing_admins`. [`stacks/50-org-iam/main.tf`](../stacks/50-org-iam/main.tf) then binds this via `google_organization_iam_member`, applying the role at Organization resource scope. [`stacks/50-org-iam/variables.tf`](../stacks/50-org-iam/variables.tf) `billing_admins` description says "Principals granted roles/billing.admin at Org scope".

**What GCP says**: `roles/billing.admin` has **lowest-level grantable resource = Billing Account**, not Organization. The role's permissions are designed to administer a specific Billing Account (`billingAccounts/<id>`), which sits outside the Resource Manager tree (as documented in [architecture.md &mdash; Cloud Billing Account section](../docs/architecture.md)). Binding it at Organization scope with `google_organization_iam_member` does not match the role's intended scope semantics.

**What was probably intended**: two possibilities, requiring a decision:

1. **`roles/billing.creator` at Org scope** &mdash; if the intent is to grant principals the ability to **create new Billing Accounts** at the Organization level. This is genuinely Org-scope IAM and belongs in this stack (just rename the variable to `billing_creators` and swap the role).
2. **`roles/billing.admin` at Billing Account scope** &mdash; if the intent is to grant principals the ability to **administer an existing Billing Account** (link projects, manage IAM on the account, close it). This requires a different resource (`google_billing_account_iam_member`) targeting the specific `billing_account_id` from [`00-org-baseline`](../stacks/00-org-baseline/) output. This is not Org-scope IAM strictly speaking &mdash; it's Billing IAM. It may deserve either a separate stack (`50-billing-iam` or similar) or a subsection here with a clear note about scope.

**Fix direction**:
1. Decide the intent (Billing Account creation vs administration of an existing Billing Account).
2. If (1): rename `billing_admins` &rarr; `billing_creators`, swap role to `roles/billing.creator`, keep in this stack.
3. If (2): remove `billing_admins` from the curated set here, create a dedicated Billing IAM binding (either in a new stack or a clearly-scoped subsection using `google_billing_account_iam_member`).
4. Update `50-org-iam` README + ADR + control-mapping accordingly.
5. The `billing_admins` row in the stack README is already flagged (v0.4.11) pointing at this correction.

Not blocking operation &mdash; `google_organization_iam_member` accepts the binding syntactically. But the effective permissions granted at Org scope for this role may not match operator expectations, and it violates the "role + scope = blast radius" principle documented in [`50-org-iam` README](../stacks/50-org-iam/README.md).

## From section 60 review (tags)

### △/✕ Under review: `purpose = "GCE_FIREWALL"` as default for every TagKey

**Where**: [`stacks/60-tags/main.tf`](../stacks/60-tags/main.tf) sets `purpose = "GCE_FIREWALL"` on every `google_tags_tag_key` in the reference catalog (`environment`, `data-classification`, `cost-center`, `owner`, plus any `custom_tag_keys`). [ADR-0014 "Why purpose = GCE_FIREWALL"](adr/0014-tag-catalog-choice.md) justifies this as "the maximally-capable choice for all reference keys" with "no downside".

**What needs verification**:

1. **Specific GCP semantics of `purpose = GCE_FIREWALL`**. This value activates the TagKey as a "secure tag" usable in Network Firewall Policies. The claim in ADR-0014 that this is a strictly-additive capability (does not affect IAM/billing/org-policy uses) needs verification against current GCP documentation. Secure tags have lifecycle and IAM implications that general-purpose Resource Manager Tags do not.
2. **Whether it is appropriate for governance-only tags**. `cost-center` and `owner` have no meaningful firewall use case. Setting `GCE_FIREWALL` on them is defensible only if there is no downside; if there is any (extra IAM permission required to bind, extra API surface, extra billing, extra audit noise, changed inheritance behaviour, ...), then a `data_only` purpose (or the default no-purpose) would be more appropriate for those keys.
3. **Irreversibility**. As ADR-0014 itself acknowledges, `purpose` cannot be changed after creation without recreating the TagKey (which destroys the value tree and breaks any binding). This raises the bar for accepting "maximally-capable, no downside" &mdash; the decision must be right the first time.

**Possible outcomes of the research**:

- **Confirm current default is correct**: research shows `GCE_FIREWALL` is genuinely inocuous for governance tags. Then update ADR-0014 with the specific evidence (which GCP docs, which sections) that supports the "no downside" claim, remove the ⚠ Under review notice, and consider the item closed.
- **Split the purpose per tag class**: if `GCE_FIREWALL` has non-trivial semantics for governance tags, split the catalog into:
  - Governance tags (`environment`, `data-classification`, `cost-center`, `owner`) with no firewall-specific purpose &mdash; used for IAM Conditions, billing, org-policy.
  - Future secure-tag catalog (`app-tier`, `security-zone`, `inspection-required`, `trust-zone`, etc.) with `GCE_FIREWALL` &mdash; used for Network Firewall Policies.
  
  This is the split conceptually sketched in the section 60 review and would replace the "one purpose fits all" default with an intentional taxonomy per use case.

**Fix direction**: this is one of the few pending items that is genuinely research-then-decide, not code-fix-only. The code change itself is small (change one line per tag key or introduce a per-key purpose in the variable schema); the decision about what to change to is what needs the research.

**Not blocking operation**: the current default works; the concern is about whether it is the *right* default for a decision that cannot be changed later without pain.

## Convention for using this file

- Each item lands here when a review section identifies it and stays here until a code release fixes it.
- Fixes come in code releases (not doc-only patches), grouped by theme where possible (e.g. a `v0.5.0` might address all `stacks/30-org-policies/` bugs at once).
- When an item is fixed, remove it from this file in the same commit that applies the fix. The commit message references the item.
- This file is portfolio-honest: it says "review found these; fix cycle is upcoming". It is not a bug tracker for issues found during real deployment (those go through GitHub Issues on the repo).
