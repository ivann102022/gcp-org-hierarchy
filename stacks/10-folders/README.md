<!--
File:        stacks/10-folders/README.md
Author:      Ismael Cruz
Version:     0.2.0
Description: Documentation for the folders stack — provisions or references
             the GCP folder tree with depth up to 3, using composite keys
             for LandingZones environment grandchildren.
-->

# Stack `10-folders`

Provisions (or references) the GCP folder tree. Publishes `folder_ids` (plus scoped subsets) for stack `20-projects` to attach platform projects to, and for downstream repos that place their own resources under specific folders.

## What it owns

- `google_folder.roots` &mdash; folders whose parent is the Organization. Reference set: `Platform`, `LandingZones`, `Sandbox`.
- `google_folder.children` &mdash; folders whose parent is a root. Reference set: `Logs`, `Management`, `IAM`, `DNS`, `Ingress` under `Platform`; `HUB`, `HostPrj`, `ServicePrj` under `LandingZones`.
- `google_folder.grandchildren` &mdash; folders whose parent is a child. Reference set: `PRO`, `PRE`, `DEV` under both `HostPrj` and `ServicePrj` (six grandchildren total by default).
- All three blocks in `create` mode. In `existing` mode the stack is read-only: `folder_ids` echoes `var.existing_folder_ids`.

## Reference folder tree (v0.2.0)

```
Organization (emp.com)
├── Platform                       [root]
│   ├── Logs                       [child]        → home of plogs
│   ├── Management                 [child]        → home of pmgm
│   ├── IAM                        [child]        → home of piam
│   ├── DNS                        [child]        → home of pdns
│   └── Ingress                    [child]        → home of pingress
├── LandingZones                   [root]
│   ├── HUB                        [child, flat]         → home of pnet-hub (LZ-owned)
│   ├── HostPrj                    [child, env-split]
│   │   ├── PRO                    [grandchild]          → home of pnet-pro (LZ-owned)
│   │   ├── PRE                    [grandchild]          → home of pnet-pre (LZ-owned)
│   │   └── DEV                    [grandchild]          → home of pnet-dev (LZ-owned)
│   └── ServicePrj                 [child, env-split]
│       ├── PRO                    [grandchild]          → home of srv-pro (LZ-owned)
│       ├── PRE                    [grandchild]          → home of srv-pre (LZ-owned)
│       └── DEV                    [grandchild]          → home of srv-dev (LZ-owned)
└── Sandbox                        [root, flat]          → home of sandbox
```

Rationale for the split:

- **`Platform` has one child per platform project (1:1)** &mdash; enables granular IAM scoping (`roles/dns.admin` on `DNS` folder applies only to `pdns`), per-folder org policies, and clean audit surfaces. See [ADR-0005](../../docs/adr/0005-folder-per-platform-project.md).
- **`LandingZones` has three second-level children** &mdash; `HUB` (shared across environments, no env sub-folders), `HostPrj` and `ServicePrj` (each split by environment `PRO/PRE/DEV`). Encodes the GCP Shared VPC host-vs-service lifecycle split at the folder level. See [ADR-0006](../../docs/adr/0006-landing-zones-hostprj-serviceprj-env-split.md).
- **`Sandbox` stays flat** &mdash; a single sandbox project by default; expand with `custom_folders` if per-team sandboxes are needed.

## Composite keys for grandchildren

`PRO` (and `PRE`, `DEV`) appears under both `HostPrj` and `ServicePrj`. GCP allows this because display-name uniqueness is enforced *per parent*, not globally. Terraform's flat map needs unique keys, so grandchild folders are keyed as **`<parent>-<env>`**:

| Composite key | Display name in GCP | Parent |
|---|---|---|
| `HostPrj-PRO` | `PRO` | `HostPrj` |
| `HostPrj-PRE` | `PRE` | `HostPrj` |
| `HostPrj-DEV` | `DEV` | `HostPrj` |
| `ServicePrj-PRO` | `PRO` | `ServicePrj` |
| `ServicePrj-PRE` | `PRE` | `ServicePrj` |
| `ServicePrj-DEV` | `DEV` | `ServicePrj` |

Downstream consumers look up `folder_ids["HostPrj-PRO"]`, not `folder_ids["PRO"]`. See [ADR-0006](../../docs/adr/0006-landing-zones-hostprj-serviceprj-env-split.md#composite-keys).

## How the tree is provisioned

Three-pass model matching the three depths:

1. **`google_folder.roots`** &mdash; every folder with `parent_key = "__org__"`. Parent is `data.google_organization.this.name` (from `00-org-baseline`).
2. **`google_folder.children`** &mdash; every folder whose `parent_key` is a root key. Parent is `google_folder.roots[each.value.parent_key].name`.
3. **`google_folder.grandchildren`** &mdash; every folder whose `parent_key` is a child key. Parent is `google_folder.children[each.value.parent_key].name`.

Custom folders declared in `var.custom_folders` fall into whichever depth their `parent_key` implies. Custom folders 4+ levels deep are not supported in v0.2.0 (extend by adding a `google_folder.great_grandchildren` block when the need arises &mdash; portfolio has no consumer today).

## Modes

- **`create`**: provisions the folders declared in the reference tree + `custom_folders`. Each folder ships with `deletion_protection = true`.
- **`existing`**: no resources. `folder_ids` is populated from `var.existing_folder_ids` (operator provides the map explicitly; GCP has no by-display-name folder lookup data source at the org scope).

## Migration from v0.1.0

The v0.1.0 default children under `Platform` were `Identity`, `Management`, `Connectivity` (3 folders, discipline-grouped). v0.2.0 changes to `Logs`, `Management`, `IAM`, `DNS`, `Ingress` (5 folders, 1:1 per project &mdash; see [ADR-0005](../../docs/adr/0005-folder-per-platform-project.md)).

The stack does **not** ship `moved` blocks for the folder rename &mdash; that would fire for every fresh deployment too. Migration path per deployment type:

- **Fresh v0.2.0 deployment** &mdash; apply directly; the new tree is created.
- **Upgrading a live v0.1.0 deployment** &mdash; the three old folders (`Identity`, `Management`, `Connectivity`) remain in the Org after apply but are no longer referenced by this stack. Two options for the operator:
  1. Delete them via console (they'll be empty because `20-projects` re-parents its projects to the new folders in the same apply cycle &mdash; see the `platform_project_home_folder` default).
  2. Re-add them via `var.custom_folders` if you want to preserve the old folders alongside the new ones during a phased migration.

The project-side migration is handled inside `stacks/20-projects/main.tf` via existing `moved` blocks that preserve state addresses when projects re-parent between folders.

## Inputs

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `org_baseline_state_bucket` | Yes | &mdash; | Remote-state bucket for `00-org-baseline`. |
| `org_baseline_state_prefix` | No | `"gcp-org-hierarchy/00-org-baseline"` | Override only if that stack's `backend.tf` prefix changed. |
| `enable_folders` | No | `false` | Master switch (default no-op). |
| `organization_mode` | No | `"existing"` | `existing` or `create`. |
| `create_reference_folder_tree` | No | `true` | Whether to provision the reference set in `create` mode. |
| `reference_platform_children` | No | `["Logs", "Management", "IAM", "DNS", "Ingress"]` | 1:1 folders under `Platform`. |
| `reference_landing_zone_children` | No | `{HUB={has_environments=false}, HostPrj={has_environments=true}, ServicePrj={has_environments=true}}` | Second-level children under `LandingZones`. |
| `reference_landing_zone_environments` | No | `["PRO", "PRE", "DEV"]` | Env sub-folder names, applied under every LZ child with `has_environments = true`. |
| `custom_folders` | No | `{}` | Additional folders. `parent_key = "__org__"` or the key of any folder (reference or custom). |
| `existing_folder_ids` | Yes (in `existing` mode) | `{}` | Map of folder key &rarr; `"folders/<id>"`. |

Full spec in [`variables.tf`](variables.tf).

## Outputs

| Output | Type | Purpose |
|---|---|---|
| `folder_ids` | `map(string)` | Every folder (roots + children + grandchildren + customs) keyed by folder key. |
| `root_folder_ids` | `map(string)` | Subset limited to direct children of the Organization. |
| `platform_child_folder_ids` | `map(string)` | Subset limited to Platform's children (Logs / Management / IAM / DNS / Ingress). Consumed by `20-projects`. |
| `landing_zone_env_folder_ids` | `map(string)` | Subset limited to LandingZones env grandchildren (`HostPrj-PRO`, `ServicePrj-DEV`, etc.). Consumed by Tier 2 LZs. |
| `mode` | `string` | Echo of `organization_mode`. |

Full spec in [`../../docs/contract.md`](../../docs/contract.md).

## Required IAM

- `roles/resourcemanager.folderCreator` at the Organization scope (`create` mode only).
- `roles/resourcemanager.folderViewer` at the Organization scope (both modes).

## Apply

```bash
terraform -chdir=stacks/10-folders init
terraform -chdir=stacks/10-folders plan
terraform -chdir=stacks/10-folders apply
```

## Failure modes

- **Duplicate display name at same parent**: `google_folder` requires uniqueness of `display_name` within a parent. Common trigger when re-running `create` against an Org where folders already exist &mdash; switch to `existing` mode.
- **Cyclic parent_key in `custom_folders`**: caught at plan time by the precondition block.
- **`custom_folders` entry pointing at a nonexistent parent_key**: caught at plan time.
- **Missing `existing_folder_ids` in `existing` mode with `enable_folders = true`**: caught at plan time.
- **`terraform destroy`**: folders ship with `deletion_protection = true`. Destroy fails with a clear error. To genuinely destroy, flip the flag, apply, then destroy.
