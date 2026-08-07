<!--
File:        stacks/50-org-iam/README.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Placeholder for the org-iam stack — planned for v0.3.0.
             Not yet scaffolded with HCL.
-->

# Stack `50-org-iam` (planned v0.3.0)

Organization-scope IAM bindings for the minimum privileged principals that must exist for Tier 0 itself to function: Org Admin, Project Creator, Billing Admin, Security Admin, and a break-glass user.

**Not yet implemented.** Scaffolded as an empty directory to reserve the stack number and document intent. Implementation lands in v0.3.0.

## What this stack does NOT do

- Does not manage Workforce Identity Federation &mdash; that lives in `gcp-identity-baseline` (Tier 1). See [ADR-0004](../../docs/adr/0004-no-workforce-identity-federation-here.md).
- Does not create custom roles &mdash; those live in `gcp-identity-baseline` where the identity discipline lives.
- Does not manage group membership &mdash; groups themselves come from Cloud Identity / Workspace, managed outside Terraform.

## Planned inputs

- `enable_org_iam` &mdash; master switch.
- `org_admins`, `project_creators`, `billing_admins`, `security_admins`, `break_glass_users` &mdash; per-role principal lists.

## Planned outputs

- `org_iam_role_bindings` &mdash; role &rarr; list of principals.

## Cross-references

- [../../docs/architecture.md](../../docs/architecture.md) &mdash; section "`50-org-iam` (planned v0.3.0)".
