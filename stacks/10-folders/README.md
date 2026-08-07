<!--
File:        stacks/10-folders/README.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Documentation for the folders stack — provisions or references
             the GCP folder tree using a two-pass root/child split.
-->

# Stack `10-folders`

Provisions (or references) the GCP folder tree. Publishes `folder_ids` for stack `20-projects` to attach platform projects to, and for downstream repos that place their own resources under specific folders.

## What it owns

- `google_folder.roots` &mdash; folders whose parent is the Organization. Reference set: `Platform`, `LandingZones`, `Sandbox`.
- `google_folder.children` &mdash; folders whose parent is another folder key. Reference set: `Production`, `NonProduction` (opt-in) under `LandingZones`, plus anything the operator adds via `custom_folders`.
- Both blocks in `create` mode. In `existing` mode the stack is read-only: `folder_ids` echoes `var.existing_folder_ids`.

## Reference folder tree

```
Organization
├── Platform            # for plogs, pmgm, pident, pdns, pingress (stack 20)
├── LandingZones        # parent of every Tier 2 LZ's projects
│   ├── Production      # opt-in via reference_landing_zone_children
│   └── NonProduction   # opt-in via reference_landing_zone_children
└── Sandbox             # for psandbox (stack 20)
```

Rationale for the split: `Platform` isolates the org's shared services from tenant workloads; `LandingZones` is where each LZ's projects (and its own sub-tree) land; `Sandbox` is the ephemeral experimentation zone with looser policies. Aligned with Google Cloud Foundation Fabric.

## How the tree is provisioned

Flat map with a `parent_key` reference (same pattern as `aws-org-hierarchy/stacks/10-ous`). Two passes:

1. **`google_folder.roots`** &mdash; every folder with `parent_key = "__org__"`. Parent is `data.google_organization.this.name` (from `00-org-baseline`).
2. **`google_folder.children`** &mdash; every folder with `parent_key = "<other folder key>"`. Parent is `google_folder.roots[each.value.parent_key].name`, which forces the dependency graph to sequence roots before children.

For deeper nesting (grand-children), the pattern generalises &mdash; but v0.1.0 restricts to 2 depth levels. Custom folders can attach to any root or opt-in reference child.

## Modes

- **`create`**: provisions the folders declared in the reference tree + `custom_folders`. Each folder ships with `deletion_protection = true` (Terraform will not `destroy` unless the flag is flipped).
- **`existing`**: no resources. `folder_ids` is populated from `var.existing_folder_ids`. Required because GCP has no by-display-name folder lookup data source at the org scope &mdash; operator provides the map explicitly.

## Inputs

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `org_baseline_state_bucket` | Yes | &mdash; | Remote-state bucket for `00-org-baseline`. |
| `org_baseline_state_prefix` | No | `"gcp-org-hierarchy/00-org-baseline"` | Override only if that stack's `backend.tf` prefix changed. |
| `enable_folders` | No | `false` | Master switch (default no-op). |
| `organization_mode` | No | `"existing"` | `existing` or `create`. |
| `create_reference_folder_tree` | No | `true` | Whether to provision `Platform` / `LandingZones` / `Sandbox` in `create` mode. |
| `reference_landing_zone_children` | No | `[]` | Opt-in sub-folders under `LandingZones` (e.g. `["Production", "NonProduction"]`). |
| `custom_folders` | No | `{}` | Additional folders. `parent_key = "__org__"` or another folder key. |
| `existing_folder_ids` | Yes (in `existing` mode) | `{}` | Map of display name &rarr; `"folders/<id>"`. |

Full spec in [`variables.tf`](variables.tf).

## Outputs

| Output | Type | Purpose |
|---|---|---|
| `folder_ids` | `map(string)` | Display name &rarr; `"folders/<id>"`. Consumed by stack `20-projects` and every downstream repo. |
| `root_folder_ids` | `map(string)` | Subset of `folder_ids` limited to direct children of the Organization. |
| `mode` | `string` | Echo of `organization_mode`. |

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
- **Missing `existing_folder_ids` in `existing` mode with `enable_folders = true`**: caught at plan time.
- **`terraform destroy`**: folders ship with `deletion_protection = true`. Destroy fails with a clear error. To genuinely destroy, flip the flag, apply, then destroy.
