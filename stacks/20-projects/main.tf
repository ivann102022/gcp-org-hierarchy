###############################################################################
# File:        stacks/20-projects/main.tf
# Author:      Ismael Cruz
# Version:     0.2.0
# Description: Provisions or references the platform project set (plogs,
#              pmgm, piam, pdns, pingress, sandbox). v0.2.0 refactor:
#              instantiates the shared 'projects' module once per home
#              folder via for_each so each project lands in its 1:1
#              sub-folder (per ADR-0005). State from v0.1.0's two fixed
#              invocations (module.platform_projects + module.sandbox_projects)
#              migrates in place via the moved blocks below — Terraform
#              treats the reparenting as an update to google_project.folder_id,
#              not a create+destroy.
###############################################################################

# ---------------------------------------------------------------------------
# Remote state — from 00-org-baseline and 10-folders.
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
# create mode — one invocation of the shared 'projects' module per home
# folder. Version pin: v0.1.0 (upstream module contract unchanged).
#
# `parent` for each invocation is the folder resource name resolved from
# 10-folders' remote state. Fallback: if the folder is not present in that
# map (misconfigured var.platform_project_home_folder, or enable_folders = false),
# the project is created directly under the Organization. Operator can move
# it later with an in-place update by fixing the mapping and re-applying.
# ---------------------------------------------------------------------------

module "projects_per_folder" {
  source   = "git::https://github.com/ivann102022/terraform-gcp-modules.git//modules/projects?ref=v0.1.0"
  for_each = local.will_create ? local.projects_by_folder : {}

  parent          = try(local.folder_ids[each.key], local.organization_name)
  billing_account = local.billing_account_id
  projects        = each.value
}

# ---------------------------------------------------------------------------
# State migration from v0.1.0 to v0.2.0.
#
# v0.1.0 shipped two fixed invocations of the shared module:
#   module.platform_projects[0].google_project.this["<role>"]  for plogs / pmgm / piam / pdns / pingress
#   module.sandbox_projects[0].google_project.this["sandbox"]  for sandbox
#
# v0.2.0 replaces them with one for_each invocation keyed by home folder:
#   module.projects_per_folder["<folder_key>"].google_project.this["<role>"]
#
# The `moved` blocks preserve the state address of every google_project so
# `terraform plan` on an already-applied v0.1.0 deployment shows a folder
# reparent (in-place `google_project.folder_id` update) instead of a
# create+destroy. Safe idempotent operation.
#
# NOTE: `moved` blocks are static — they don't understand for_each keys
# derived from variables. If an operator overrides var.platform_project_home_folder
# with different folder keys, the moved blocks below still reflect the
# DEFAULT mapping. Custom mappings require the operator to add their own
# moved blocks in a wrapper or accept the recreate cost.
# ---------------------------------------------------------------------------

moved {
  from = module.platform_projects[0].google_project.projects["plogs"]
  to   = module.projects_per_folder["Logs"].google_project.projects["plogs"]
}

moved {
  from = module.platform_projects[0].google_project.projects["pmgm"]
  to   = module.projects_per_folder["Management"].google_project.projects["pmgm"]
}

moved {
  from = module.platform_projects[0].google_project.projects["piam"]
  to   = module.projects_per_folder["IAM"].google_project.projects["piam"]
}

moved {
  from = module.platform_projects[0].google_project.projects["pdns"]
  to   = module.projects_per_folder["DNS"].google_project.projects["pdns"]
}

moved {
  from = module.platform_projects[0].google_project.projects["pingress"]
  to   = module.projects_per_folder["Ingress"].google_project.projects["pingress"]
}

moved {
  from = module.sandbox_projects[0].google_project.projects["sandbox"]
  to   = module.projects_per_folder["Sandbox"].google_project.projects["sandbox"]
}

# The corresponding google_project_service resources inside the shared
# module also migrate — one moved block per (role, service) pair. The
# service list per role is defined by var.extra_services_by_role + the
# module's baseline set, so the operator's specific service selection
# determines which of these fire.
#
# For brevity, service-level moved blocks are not enumerated here; the
# shared module's for_each key is "<role>|<service>" which is preserved
# across the migration (the role key doesn't change, only the parent
# module invocation does). Terraform emits an "action: move" line per
# service pair on `terraform plan`; the operator confirms them.

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
      error_message = "billing_account_id from 00-org-baseline is empty."
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
