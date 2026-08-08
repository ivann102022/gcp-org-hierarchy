<!--
File:        stacks/20-projects/README.md
Author:      Ismael Cruz
Version:     0.2.0
Description: Documentation for the platform-projects stack — provisions or
             references the six reference platform projects, placing each
             in its 1:1 home sub-folder per the v0.2.0 reference tree.
-->

# Stack `20-projects`

Provisions (or references) the six reference **platform projects** &mdash; the containers that every Tier 1 baseline deploys into and every Tier 2 LZ consumes. Publishes `platform_project_ids` for the entire portfolio to consume via `terraform_remote_state`.

## Reference project set (v0.2.0)

Keys align with the existing GCP LZs' `existing_project_ids` map so consumers do not need a key-rename shim. Home folders reflect the 1:1 folder-per-platform-project decision from [ADR-0005](../../docs/adr/0005-folder-per-platform-project.md):

| Role key | Default project ID | Purpose | Home folder (v0.2.0) |
|---|---|---|---|
| `plogs` | `gcp0-prj-emp-plogs-01` | Centralized logs, org-sink destination | `Logs` (under `Platform`) |
| `pmgm` | `gcp0-prj-emp-pmgm-01` | KMS central + management | `Management` (under `Platform`) |
| `piam` | `gcp0-prj-emp-piam-01` | Identity foundation (WIF pool created by `gcp-identity-baseline`) | `IAM` (under `Platform`) |
| `pdns` | `gcp0-prj-emp-pdns-01` | Cloud DNS host (zones created by `gcp-dns-baseline`) | `DNS` (under `Platform`) |
| `pingress` | `gcp0-prj-emp-pingress-01` | Shared ingress baseline (Global External LB + Cloud Armor + WAF, VPC created by future `gcp-ingress-baseline`) | `Ingress` (under `Platform`) |
| `sandbox` | `gcp0-prj-emp-sandbox-01` | Single-instance sandbox | `Sandbox` (root) |

## What it owns

- One invocation of the shared `git::…/terraform-gcp-modules.git//modules/projects?ref=v0.1.0` module **per distinct home folder**, via `for_each` over `local.projects_by_folder`.
- With the default `platform_project_home_folder` mapping, each folder holds exactly one project (six invocations, one per project — reflects the 1:1 shape). Overrides that group multiple roles into one folder collapse the invocations accordingly.

## What it does NOT do

- Does not create folders &mdash; that's stack `10-folders`. This stack reads folder IDs from that stack's remote state.
- Does not configure the log sink, KMS keys, DNS zones, or IAM inside the projects &mdash; those are Tier 1 baselines. Rationale in [ADR-0002](../../docs/adr/0002-platform-projects-here-not-in-lz.md) and [ADR-0003](../../docs/adr/0003-org-sink-in-tier0-not-obs-baseline.md).
- Does not create tenant VPC hosts (`pnet-hub`, `pnet-pro`, ...) &mdash; those are the LZ's concern. LZs place them under `LandingZones/HUB`, `LandingZones/HostPrj/PRO`, etc. (see [10-folders README](../10-folders/README.md)).

## Modes

- **`create`**: provisions the reference set. Every project inherits `deletion_policy = "PREVENT"` from the `google` provider default (&ge; v6), so `terraform destroy` fails safely.
- **`existing`**: no resources. `platform_project_ids` is populated from `var.existing_project_ids` filtered to enabled roles.

## Fallback when a home folder is missing

If a role's home folder is not present in `10-folders`' `folder_ids` output (misconfigured `platform_project_home_folder` value, or `enable_folders = false` in that stack), the invocation falls back to `parent = local.organization_name` &mdash; the project is created directly under the Organization root. Operator can fix the mapping and re-apply; `google_project.folder_id` updates in place, no recreation.

## Migration from v0.1.0

v0.1.0 shipped two fixed module invocations (`module.platform_projects` for Platform-folder projects, `module.sandbox_projects` for sandbox). v0.2.0 replaces them with a single `for_each` invocation keyed by home folder (`module.projects_per_folder["Logs"]`, `["Management"]`, ...).

The stack ships `moved` blocks in [`main.tf`](main.tf) that preserve state addresses across the refactor for every project in the default mapping. `terraform plan` on an already-applied v0.1.0 deployment shows an in-place `google_project.folder_id` update per project (project moves from `Platform` folder to its new 1:1 folder) &mdash; **no recreation**.

If the operator uses a custom `platform_project_home_folder`, they must add their own `moved` blocks in a wrapper to preserve state (or accept the recreate cost, which fails on `deletion_policy = "PREVENT"` anyway &mdash; two-step protection).

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
| `platform_project_home_folder` | No | 1:1 mapping (see table above) | Role &rarr; folder key. |
| `existing_project_ids` | Yes (in `existing` mode) | `{}` | Role &rarr; project ID map. |

Full spec in [`variables.tf`](variables.tf).

## Outputs

| Output | Type | Purpose |
|---|---|---|
| `platform_project_ids` | `map(string)` | Consumed by every Tier 1 baseline and Tier 2 LZ. |
| `platform_project_numbers` | `map(string)` | Numeric IDs for IAM bindings that need them. Empty in `existing` mode. |
| `platform_project_names` | `map(string)` | Display names. Empty in `existing` mode. |
| `platform_project_home_folders` | `map(string)` | Role &rarr; folder key. New in v0.2.0; useful for downstream stacks that scope resources by home folder. |
| `mode` | `string` | Echo of `organization_mode`. |

Full contract in [`../../docs/contract.md`](../../docs/contract.md).

## Required IAM

- `roles/resourcemanager.projectCreator` at the parent folder scope of each home folder (`Logs`, `Management`, `IAM`, `DNS`, `Ingress`, `Sandbox` by default). If any home folder falls back to the Org root, then Org-scope `projectCreator` too.
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
- **Home folder key not in `folder_ids`**: falls back to Org root with a console warning at plan time (via precondition). Fix the mapping or add the folder to `10-folders` and re-apply.
- **Billing account not attached**: if `billing_account_id` from `00-org-baseline` is wrong or the executing identity lacks `roles/billing.user`, `google_project.billing_account` errors with a clear message.
- **API enablement lag**: `google_project_service` occasionally reports a project as "not fully provisioned" on the first apply. Re-apply after 60 seconds resolves it.
- **`terraform destroy`**: fails on `deletion_policy = "PREVENT"`. To genuinely destroy, override the policy per project (via `lifecycle` in a wrapper), apply, then destroy. Two-step protection is intentional.
