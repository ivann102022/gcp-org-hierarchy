<!--
File:        stacks/50-org-iam/README.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Documentation for the org-iam stack — org-scope IAM bindings
             for the minimum privileged role set + break-glass model.
-->

# Stack `50-org-iam`

Provisions **org-scope IAM bindings** for the minimum privileged role set that must exist at Organization scope for the portfolio to function. Uses `google_organization_iam_member` (per-member) rather than `google_organization_iam_binding` (authoritative per-role) so this stack does not stomp on bindings created outside Terraform for the same role.

Break-glass model documented in [ADR-0013](../../docs/adr/0013-break-glass-user-model.md).

## What it owns

- `google_organization_iam_member.curated` &mdash; one resource per (role, member) pair for the curated role set.
- `google_organization_iam_member.custom` &mdash; one resource per (role, member) pair from `custom_org_iam_bindings`.

## Curated role set

| Variable | Role | Typical membership |
|---|---|---|
| `org_admins` | `roles/resourcemanager.organizationAdmin` | Small platform-admin group. Most privileged role in GCP &mdash; treat with matching operational discipline. |
| `project_creators` | `roles/resourcemanager.projectCreator` | Terraform SA(s) that run Tier 0 stack `20-projects` + any LZ that has `create_projects = true` fallback. |
| `billing_admins` | `roles/billing.admin` | Finance-approved small group. |
| `security_admins` | `roles/iam.securityAdmin` | SecOps team. Grants ability to modify IAM policies org-wide. |
| `logging_admins` | `roles/logging.admin` | Terraform SA for `40-org-logging` + observability team. |
| `orgpolicy_admins` | `roles/orgpolicy.policyAdmin` | Terraform SA for `30-org-policies`. |
| `org_viewers` | `roles/resourcemanager.organizationViewer` | Broad low-privilege read access. Safe to grant to auditors + on-call engineers. |
| `break_glass_principals` | `roles/resourcemanager.organizationAdmin` (dedicated binding) | Dedicated group whose membership is empty by default. See ADR-0013. |

`break_glass_principals` is separated from `org_admins` so an alert (in `gcp-observability-baseline`) can fire specifically when a break-glass principal performs an action.

## Explicitly excluded

- **Workforce Identity Federation** &mdash; project-scope resource that belongs in `gcp-identity-baseline` (Tier 1). See [ADR-0004](../../docs/adr/0004-no-workforce-identity-federation-here.md).
- **Custom roles** (`google_organization_iam_custom_role`) &mdash; identity discipline; belongs in `gcp-identity-baseline`.
- **Folder- or project-scope IAM bindings** &mdash; those live at their respective scopes (managed by the folder or project owner).
- **IAM Conditions** on org-scope bindings &mdash; not in v0.1.0 of this stack. Add via `custom_org_iam_bindings` with your own resource definitions when needed.

## Why `google_organization_iam_member` (not `_binding` or `_policy`)

Three resource types exist for org IAM:

- `google_organization_iam_policy` &mdash; authoritative on the entire org IAM policy. **Never use** &mdash; overwrites everything (including Workspace super-admin, GCP-managed service agents). Recovery from a bad apply is manual and slow.
- `google_organization_iam_binding` &mdash; authoritative per role. If Terraform manages `roles/resourcemanager.organizationAdmin`, any binding for that role added outside Terraform (console, gcloud) is removed on next apply. Dangerous.
- `google_organization_iam_member` &mdash; per member. Adds/removes one (role, member) pair without touching other bindings for the same role.

I use `_member` for the same reason I use `google_project_iam_member` throughout the portfolio: **compose don't own**. This stack owns the bindings it declares; other bindings for the same role coexist safely.

## Inputs

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `org_baseline_state_bucket` | Yes | &mdash; | Remote state for `00-org-baseline`. |
| `enable_org_iam` | No | `false` | Master switch. |
| `org_admins`, `project_creators`, ... `org_viewers` | No | `[]` each | Curated role member lists. |
| `break_glass_principals` | No | `[]` | Dedicated break-glass principals. See ADR-0013. |
| `custom_org_iam_bindings` | No | `{}` | Map of binding_key &rarr; { role, members }. |

Full spec in [`variables.tf`](variables.tf).

## Outputs

| Output | Type | Purpose |
|---|---|---|
| `org_iam_bindings` | `map(list(string))` | Role &rarr; list of members. Consumed by audit tools. |
| `custom_org_iam_bindings` | `map(object)` | Echo of custom bindings. |
| `break_glass_configured` | `bool` | Whether break-glass principals are set. Consumed by obs-baseline alert precondition. |
| `break_glass_principals` | `list(string)` | Echo of break-glass principals. Consumed by obs-baseline alert filter. |

Full contract in [`../../docs/contract.md`](../../docs/contract.md).

## Required IAM

- `roles/resourcemanager.organizationAdmin` at the Organization scope. The most privileged GCP role &mdash; treat the credentials that hold it with matching operational discipline (ephemeral, short-lived, audit-logged).

## Apply

```bash
terraform -chdir=stacks/50-org-iam init
terraform -chdir=stacks/50-org-iam plan
terraform -chdir=stacks/50-org-iam apply
```

## Failure modes

- **Empty `org_admins` and empty `break_glass_principals` with `enable_org_iam = true`**: caught at plan time by precondition. Rationale: apply with no Terraform-managed Org Admin binding is almost certainly a misconfiguration.
- **Principal format error** (missing `user:` / `group:` prefix): caught at plan time.
- **Removing a member from a role list**: on next apply, that (role, member) binding is deleted &mdash; the user loses the role. If they need it back, add them and re-apply. No accidental cross-member removal because bindings are per-member.
- **Applying with a principal that doesn't exist in Cloud Identity**: `google_organization_iam_member` accepts the binding syntactically (GCP does not validate that the principal exists at IAM binding time). The binding exists but has no effect until the principal is created. Symptom: user reports they don't have the role even though tfvars says they do. Verify the principal exists in Cloud Identity / the target GCP project.
- **`terraform destroy`**: removes every curated binding. **This can lock the operator out of the Org if the destroying SA is not otherwise granted Org Admin.** Coordinate destroy with a manual break-glass procedure ready.
