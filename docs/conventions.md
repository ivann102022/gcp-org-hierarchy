<!--
File:        docs/conventions.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Coding and naming conventions for gcp-org-hierarchy. Inherits
             from the GCP LZ conventions with hierarchy-specific additions
             (organization_mode, folder naming, platform project naming,
             org policy catalogue conventions).
-->

# Coding conventions

## Licensing

Apache License 2.0 &mdash; see [`LICENSE`](../LICENSE). Per-file headers identify authorship.

## Inheritance from the GCP LZ conventions

Where this repo does not say otherwise, it follows the conventions of [`landing-zones/gcp-lz-fortinet-multiproject/docs/conventions.md`](../../../landing-zones/gcp-lz-fortinet-multiproject/docs/conventions.md):

- Global naming variables: `org_prefix` (default `gcp0`), `company` (default `emp`), `division` (default `""`), `control` (default `01`).
- Composition: `join("-", compact([...]))` so empty segments disappear.
- Header on every source file.
- `required_version >= 1.9.0`, `hashicorp/google ~> 6.14`, `hashicorp/google-beta ~> 6.14`.
- `for_each` over `count`; `count` reserved for on/off gates.

## Layered opt-in model

**Every stack has an `enable_X` layer switch** (default `false`) plus fine-grained `create_X` sub-switches. `terraform apply` with the shipped tfvars is a no-op unless the switch is flipped. This mirrors the model of the AWS sibling repo and keeps blast radius under human control.

| Stack | Master switch | Sub-switches (examples) |
|---|---|---|
| `00-org-baseline` | *(always)* &mdash; mode variable governs behaviour | `enable_essential_contacts` |
| `10-folders` | `enable_folders` | `create_reference_folder_tree`, `custom_folders` |
| `20-projects` | `enable_platform_projects` | `create_platform_projects`, per-project toggles |
| `30-org-policies` | `enable_org_policies` | one `enable_<policy>` per catalogue entry |
| `40-org-logging` | `enable_org_logging` | `create_org_sink`, filter overrides |
| `50-org-iam` | `enable_org_iam` | per-role toggles |
| `60-tags` | `enable_tags` | `create_reference_tag_set`, `custom_tags` |

Preconditions between stacks are enforced via a `null_resource` block at the bottom of each stack's `main.tf` (Terraform does not allow `lifecycle {}` on `module` blocks).

## The `organization_mode` variable

Global to every stack. Two valid values with a `validation` block:

```hcl
variable "organization_mode" {
  description = "Reserved for future modes; only 'existing' and 'create' are valid in v0.1.0."
  type        = string
  default     = "existing"
  validation {
    condition     = contains(["existing", "create"], var.organization_mode)
    error_message = "organization_mode must be 'existing' or 'create'."
  }
}
```

Each stack gates its resources on the mode:

```hcl
resource "google_folder" "reference" {
  for_each = var.organization_mode == "create" && var.enable_folders ? var.reference_folder_tree : {}
  # ...
}

data "google_folder" "existing" {
  for_each = var.organization_mode == "existing" && var.enable_folders ? var.existing_folder_ids : {}
  folder   = each.value
}
```

Output blocks use `try()` / `coalesce` to pick the right source.

## Folder naming

Reference tree (default in `10-folders`):

```
Organization (organizations/<org_id>)
├── Platform                       (folders/xxxx)  # plogs, pmgm, piam, pdns, pingress
├── LandingZones                   (folders/yyyy)  # per-LZ subfolders (created by each LZ)
│   ├── Production                 (optional)
│   └── NonProduction              (optional)
└── Sandbox                        (folders/zzzz)  # sandbox
```

**Folder display names are PascalCase** &mdash; aligned with Google Cloud Foundation Fabric and visually distinguishing from project IDs (`snake_case_or_kebab-case`).

## Platform project naming

Naming composed from the same global variables as the GCP LZs so IDs align without operator intervention:

```
${org_prefix}-prj-${company}[-${division}]-<role>-${control}
```

Reference roles (well-known &mdash; consumed by every baseline and LZ). Keys align with the existing GCP LZs' `existing_project_ids` map so consumers do not need a key-rename shim:

| Role | Default ID (with defaults) | Purpose | Home folder |
|---|---|---|---|
| `plogs` | `gcp0-prj-emp-plogs-01` | Centralized logs, org-sink destination | `Platform` |
| `pmgm` | `gcp0-prj-emp-pmgm-01` | KMS central + management | `Platform` |
| `piam` | `gcp0-prj-emp-piam-01` | Identity foundation (WIF pool created by `gcp-identity-baseline`) | `Platform` |
| `pdns` | `gcp0-prj-emp-pdns-01` | Cloud DNS host (zones created by `gcp-dns-baseline`) | `Platform` |
| `pingress` | `gcp0-prj-emp-pingress-01` | Shared ingress baseline | `Platform` |
| `sandbox` | `gcp0-prj-emp-psandbox-01` | Single-instance sandbox (project ID uses the canonical `p` prefix; key stays `sandbox` for LZ compat) | `Sandbox` |

Consumers must **not** hardcode project IDs. Always look them up from `data.terraform_remote_state.org.outputs.platform_project_ids["<role>"]`.

## Org-policy naming (v0.2.0)

Every policy shipped in the catalogue keeps GCP's canonical constraint ID as the resource name (e.g. `iam.disableServiceAccountKeyCreation`). No `<org_prefix>` wrapping &mdash; the constraint name IS the identifier per Google's spec.

Custom policies (via `custom_org_policies`) follow:

```
<org_prefix>-orgp-<verb>-<subject>
```

Examples: `gcp0-orgp-deny-external-ip`, `gcp0-orgp-require-labels`.

## Remote state

- **Backend**: GCS with versioning enabled + uniform bucket-level access + KMS-CMEK recommended. Bucket lives in a dedicated `ptfstate` project (created by the bootstrap script, not by Terraform).
- **One prefix per stack**: `gcp-org-hierarchy/<stack-number>-<stack-name>` &mdash; e.g. `gcp-org-hierarchy/00-org-baseline`.
- **Bootstrap via [`scripts/bootstrap-tfstate.sh`](../scripts/bootstrap-tfstate.sh)** (one-time, per Organization).

Every stack keeps its own state. Never one global state across stacks or repos.

## Authentication

- **Local development**: `gcloud auth application-default login` as a user with `roles/resourcemanager.organizationAdmin` (or a subset scoped to the operations of the specific stack).
- **CI**: Workload Identity Federation into a Terraform SA that holds the org-level roles this repo needs. Service account keys are prohibited by ADR-0001 &mdash; WIF only.

## File header

Every `.tf`, `.md`, shell script, and template starts with the standard header. Version starts at `0.1.0`.

## Naming exceptions

The Organization itself has no name here &mdash; it's identified by `organization_id` (looked up from `organization_domain`). Only folders and projects get names governed by this repo.
