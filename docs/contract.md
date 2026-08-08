<!--
File:        docs/contract.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Formal output contract that gcp-org-hierarchy exposes. Every
             downstream GCP repo (baselines, landing zones, workloads)
             reads these outputs via terraform_remote_state to remain
             agnostic to whether the folder tree and platform projects
             were created by Terraform or brought in pre-existing.
-->

# Tier 0 Contract

This document is the **public API** of `gcp-org-hierarchy`. Downstream repos (`baseline-projects/gcp-*-baseline`, `landing-zones/gcp-lz-*`, future workload repos) consume it via `terraform_remote_state` and must not depend on internal implementation details of this repo.

Any change to a Required output is a **breaking change** &mdash; bump the minor version of this repo and note it in a CHANGELOG entry.

## Required outputs (shipped in v0.1.0)

Each output is emitted by a specific stack. Consumers read from that specific stack's remote state.

| Output | Type | Emitted by | Meaning |
|---|---|---|---|
| `organization_id` | `string` | `00-org-baseline` | Org ID (e.g. `"123456789012"`). Same in both modes. |
| `organization_domain` | `string` | `00-org-baseline` | Org primary domain (e.g. `"example.com"`). |
| `billing_account_id` | `string` | `00-org-baseline` | Billing account ID (e.g. `"01ABCD-234567-EFGH89"`) that platform projects attach to. |
| `mode` | `string` | `00-org-baseline` | Echoes `organization_mode`: `"existing"` / `"create"`. Consumers use it in `precondition` blocks. |
| `folder_ids` | `map(string)` | `10-folders` | Folder display-name &rarr; folder ID (`"folders/1234567890"`). Keys follow the reference tree: `Platform`, `LandingZones`, `Sandbox`, plus any custom folder. |
| `platform_project_ids` | `map(string)` | `20-projects` | Logical role &rarr; project ID. Reference keys: `plogs`, `pmgm`, `piam`, `pdns`, `pingress`, `sandbox` &mdash; aligned with the existing GCP LZs' `existing_project_ids` map. |
| `platform_project_numbers` | `map(string)` | `20-projects` | Logical role &rarr; project number (string form). Same keys as `platform_project_ids`. Needed for some IAM bindings that require project number rather than ID. |

## Optional outputs (shipped in v0.4.0)

Emitted only when the corresponding stack is enabled. Consumers should use `try()`:

### From `30-org-policies`

| Output | Type | Meaning |
|---|---|---|
| `org_policy_ids` | `map(string)` | Catalog key &rarr; policy resource name. |
| `org_policy_constraints` | `map(string)` | Catalog key &rarr; GCP constraint ID (e.g. `"iam.disableServiceAccountKeyCreation"`). |
| `org_policy_dry_run` | `map(bool)` | Catalog key &rarr; whether currently in dry-run (audit only) vs enforced. Consumers use this to filter which policies are actually blocking. |
| `custom_org_policy_ids` | `map(string)` | Custom policy name &rarr; resource name. |

### From `40-org-logging`

| Output | Type | Meaning |
|---|---|---|
| `log_sink_id` | `string` | Sink resource name (`organizations/<org_id>/sinks/<name>`). |
| `log_sink_name` | `string` | Bare sink name. |
| `log_sink_writer_identity` | `string` | `"serviceAccount:..."` &mdash; consumed by `gcp-observability-baseline` and any custom pipeline that needs to grant the sink write access to downstream destinations. |
| `log_sink_destination` | `string` | Full destination string. |
| `log_sink_include_children` | `bool` | Whether the sink captures every project in every folder. |
| `log_sink_filter` | `string` | Filter applied to the sink. |

### From `50-org-iam`

| Output | Type | Meaning |
|---|---|---|
| `org_iam_bindings` | `map(list(string))` | Role &rarr; list of members bound at Org scope. Consumed by audit tools. |
| `custom_org_iam_bindings` | `map(object)` | Echo of custom bindings. |
| `break_glass_configured` | `bool` | Whether `break_glass_principals` is non-empty. Consumed by `gcp-observability-baseline` alert-policy precondition. |
| `break_glass_principals` | `list(string)` | Echo of break-glass principals. Consumed by obs-baseline alert filter (log-based alert on `protoPayload.authenticationInfo.principalEmail` matching). |

### From `60-tags`

| Output | Type | Meaning |
|---|---|---|
| `tag_keys` | `map(string)` | Tag key short_name &rarr; `"tagKeys/<numeric_id>"`. |
| `tag_key_ids_numeric` | `map(string)` | Tag key short_name &rarr; numeric ID only. Convenience. |
| `tag_values` | `map(string)` | `"<key>/<value>"` &rarr; `"tagValues/<numeric_id>"`. |
| `tag_catalog` | `map(list(string))` | Key name &rarr; list of allowed values. Human-readable summary. |

## Consumer usage pattern

Every consumer stack in every downstream repo reads Tier 0 like this:

```hcl
data "terraform_remote_state" "org" {
  backend = "gcs"
  config = {
    bucket = var.org_state_bucket
    prefix = "gcp-org-hierarchy/20-projects"
  }
}

locals {
  platform_projects = data.terraform_remote_state.org.outputs.platform_project_ids
  log_project       = local.platform_projects.plogs
  organization_id   = data.terraform_remote_state.org.outputs.organization_id
}
```

The prefix points to whichever specific stack in `gcp-org-hierarchy` publishes the needed output. Multiple `data "terraform_remote_state"` blocks are fine when a consumer needs outputs from several Tier 0 stacks (e.g. `10-folders` for `folder_ids` + `20-projects` for `platform_project_ids`).

## Scope rules

- **`platform_project_ids` always contains all six reference keys** when stack `20-projects` is applied with defaults. Consumers can rely on `platform_project_ids["plogs"]` existing.
- **`folder_ids` may be empty** when `enable_folders = false` (the reference tree is not provisioned). Consumers that need folder IDs should check `mode` and handle the "flat structure" case (all platform projects sit directly under the Organization).
- **Modes and consumers**: consumers must handle both `mode` values equivalently. Do not put logic like `if mode == "existing"` in downstream repos &mdash; this repo hides the differences.

## Versioning

The contract itself is versioned:

- **`v0.x`** &mdash; every output subject to change without notice. Do not build production consumers.
- **`v1.0`** &mdash; first stable contract. Removals or type changes to Required outputs = major bump.

Downstream repos pin the Tier 0 repo tag (`?ref=vX.Y.Z`) and upgrade on their own schedule.

## What downstream repos MUST NOT do

- **Do not read Tier 0 state files directly** (i.e. don't reach into `default.tfstate` JSON). Use `terraform_remote_state` with the `outputs` attribute only.
- **Do not depend on undocumented outputs.** If you need something that isn't in this contract, open a change request against this repo.
- **Do not assume specific folder-tree shape** beyond the reference set. Custom folders are always possible &mdash; write code that iterates over `folder_ids` keys, not code that assumes `folder_ids["Production"]` always exists.
- **Do not create additional projects with the reserved role names** (`plogs`, `pmgm`, `piam`, `pdns`, `pingress`, `sandbox`) in a downstream repo. These names belong to Tier 0.
