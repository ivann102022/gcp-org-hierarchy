<!--
File:        stacks/20-projects/README.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Documentation for the platform-projects stack — provisions or
             references the six reference platform projects and exposes
             them via the platform_project_ids contract.
-->

# Stack `20-projects`

Provisions (or references) the six reference **platform projects** &mdash; the containers that every Tier 1 baseline deploys into and every Tier 2 LZ consumes. Publishes `platform_project_ids` for the entire portfolio to consume via `terraform_remote_state`.

## Reference project set

Keys align with the existing GCP LZs' `existing_project_ids` map so consumers do not need a key-rename shim:

| Role key | Default project ID | Purpose | Home folder |
|---|---|---|---|
| `plogs` | `gcp0-prj-emp-plogs-01` | Centralized logs, org-sink destination | `Platform` |
| `pmgm` | `gcp0-prj-emp-pmgm-01` | KMS central + management | `Platform` |
| `piam` | `gcp0-prj-emp-piam-01` | Identity foundation (WIF pool created by `gcp-identity-baseline`) | `Platform` |
| `pdns` | `gcp0-prj-emp-pdns-01` | Cloud DNS host (zones created by `gcp-dns-baseline`) | `Platform` |
| `pingress` | `gcp0-prj-emp-pingress-01` | Shared ingress baseline | `Platform` |
| `sandbox` | `gcp0-prj-emp-psandbox-01` | Single-instance sandbox (ID uses canonical `p` prefix; key stays `sandbox` for LZ compat) | `Sandbox` |

## What it owns

- Two invocations of the shared `git::…/terraform-gcp-modules.git//modules/projects?ref=v0.1.0` module:
  - `module.platform_projects` &mdash; the five projects under the `Platform` folder.
  - `module.sandbox_projects` &mdash; the one project under the `Sandbox` folder.
- The two-invocation split is required because the shared module accepts a single `parent` per invocation.

## What it does NOT do

- Does not create folders &mdash; that's stack `10-folders`. This stack reads folder IDs from that stack's remote state.
- Does not configure the log sink, KMS keys, DNS zones, or IAM inside the projects &mdash; those are Tier 1 baselines. Rationale in [ADR-0002](../../docs/adr/0002-platform-projects-here-not-in-lz.md) and [ADR-0003](../../docs/adr/0003-org-sink-in-tier0-not-obs-baseline.md).
- Does not create tenant VPC hosts (`hub`, `pnet_pro`, ...) &mdash; those are the LZ's concern.

## Modes

- **`create`**: provisions the reference set. Every project inherits `deletion_policy = "PREVENT"` from the `google` provider default (&ge; v6), so `terraform destroy` fails safely.
- **`existing`**: no resources. `platform_project_ids` is populated from `var.existing_project_ids` filtered to enabled roles.

## Fallback to Org root when folders are disabled

If `enable_folders` was `false` in stack `10-folders` (or `folder_ids["Platform"]` / `folder_ids["Sandbox"]` are otherwise unavailable), each module invocation falls back to `parent = local.organization_name`. This lets a customer deploy platform projects flat under the Organization without a folder tree &mdash; useful for demos or very small orgs.

## Inputs

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `org_baseline_state_bucket` | Yes | &mdash; | Remote-state bucket for `00-org-baseline`. |
| `folders_state_bucket` | Yes | &mdash; | Remote-state bucket for `10-folders`. |
| `enable_platform_projects` | No | `false` | Master switch. |
| `organization_mode` | No | `"existing"` | `existing` or `create`. |
| `create_reference_platform_projects` | No | `true` | Whether to provision the reference set in `create` mode. |
| `org_prefix`, `company`, `division`, `control` | No | `gcp0`/`emp`/&Oslash;/`01` | Naming segments. |
| `enable_plogs`, `enable_pmgm`, `enable_piam`, `enable_pdns`, `enable_pingress`, `enable_sandbox` | No | `true` each | Per-role opt-out. |
| `extra_services_by_role` | No | Sensible defaults per role | Extra APIs beyond the shared module's baseline. |
| `existing_project_ids` | Yes (in `existing` mode) | `{}` | Role &rarr; project ID map. |

Full spec in [`variables.tf`](variables.tf).

## Outputs

| Output | Type | Purpose |
|---|---|---|
| `platform_project_ids` | `map(string)` | Consumed by every Tier 1 baseline and Tier 2 LZ. |
| `platform_project_numbers` | `map(string)` | Numeric IDs for IAM bindings that need them. Empty in `existing` mode. |
| `platform_project_names` | `map(string)` | Display names. Empty in `existing` mode. |
| `mode` | `string` | Echo of `organization_mode`. |

Full contract in [`../../docs/contract.md`](../../docs/contract.md).

## Required IAM

- `roles/resourcemanager.projectCreator` at the parent folder scope (`Platform` and `Sandbox`, or the Org scope in the flat-fallback case).
- `roles/billing.user` on the billing account referenced by `00-org-baseline`.
- `roles/serviceusage.serviceUsageAdmin` on each project (used by the shared module to enable APIs).

## Apply

```bash
terraform -chdir=stacks/20-projects init
terraform -chdir=stacks/20-projects plan
terraform -chdir=stacks/20-projects apply
```

## Failure modes

- **Project ID collision**: `google_project` requires globally-unique project IDs. Common when re-running `create` against an Org where these IDs already exist &mdash; switch to `existing` mode.
- **Billing account not attached**: if `billing_account_id` from `00-org-baseline` is wrong or the executing identity lacks `roles/billing.user`, `google_project.billing_account` errors with a clear message.
- **API enablement lag**: `google_project_service` occasionally reports a project as "not fully provisioned" on the first apply. Re-apply after 60 seconds resolves it.
- **`terraform destroy`**: fails on `deletion_policy = "PREVENT"`. To genuinely destroy, override the policy per project (via `lifecycle` in a wrapper), apply, then destroy. Two-step protection is intentional.
