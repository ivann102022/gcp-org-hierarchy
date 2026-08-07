###############################################################################
# File:        stacks/20-projects/main.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Provisions or references the reference platform project set
#              (plogs, pmgm, piam, pdns, pingress, sandbox). In 'create'
#              mode the shared 'projects' module is instantiated twice —
#              once for the Platform folder set (5 projects) and once for
#              the Sandbox folder set (1 project) — because the module
#              accepts a single parent per invocation. In 'existing' mode
#              no resources are created; the contract is populated from
#              var.existing_project_ids.
###############################################################################

# ---------------------------------------------------------------------------
# Remote state — from 00-org-baseline (org_id, billing) and 10-folders
# (folder_ids for Platform and Sandbox).
# ---------------------------------------------------------------------------

data "terraform_remote_state" "org_baseline" {
  backend = "gcs"
  config = {
    bucket = var.org_baseline_state_bucket
    prefix = var.org_baseline_state_prefix
  }
}

data "terraform_remote_state" "folders" {
  backend = "gcs"
  config = {
    bucket = var.folders_state_bucket
    prefix = var.folders_state_prefix
  }
}

# ---------------------------------------------------------------------------
# create mode — two invocations of the shared 'projects' module. Version
# pin: v0.1.0. The parent for each invocation is the folder ID resolved
# from remote state (or falls back to the Organization if the folder is
# absent, so a customer running with enable_folders = false still gets
# projects created — they land directly under the Org).
# ---------------------------------------------------------------------------

module "platform_projects" {
  source = "git::https://github.com/ivann102022/terraform-gcp-modules.git//modules/projects?ref=v0.1.0"
  count  = local.will_create && length(local.platform_projects_input) > 0 ? 1 : 0

  parent          = try(local.folder_ids["Platform"], local.organization_name)
  billing_account = local.billing_account_id
  projects        = local.platform_projects_input
}

module "sandbox_projects" {
  source = "git::https://github.com/ivann102022/terraform-gcp-modules.git//modules/projects?ref=v0.1.0"
  count  = local.will_create && length(local.sandbox_projects_input) > 0 ? 1 : 0

  parent          = try(local.folder_ids["Sandbox"], local.organization_name)
  billing_account = local.billing_account_id
  projects        = local.sandbox_projects_input
}

# ---------------------------------------------------------------------------
# Cross-layer preconditions.
# ---------------------------------------------------------------------------

resource "null_resource" "preconditions" {
  count = var.enable_platform_projects ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.organization_id != null && local.organization_id != ""
      error_message = "organization_id from 00-org-baseline is empty. Apply 00-org-baseline first."
    }

    precondition {
      condition     = local.billing_account_id != null && local.billing_account_id != ""
      error_message = "billing_account_id from 00-org-baseline is empty. Ensure that stack was applied with a valid billing_account_id."
    }

    precondition {
      condition     = !local.will_create || can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", local.billing_account_id))
      error_message = "billing_account_id must match XXXXXX-XXXXXX-XXXXXX. Fix 00-org-baseline's input and re-apply."
    }

    precondition {
      condition     = !local.will_read || length(local.existing_ids_filtered) > 0
      error_message = "enable_platform_projects = true in 'existing' mode requires existing_project_ids populated with at least one enabled role."
    }
  }
}
