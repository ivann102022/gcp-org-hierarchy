###############################################################################
# File:        stacks/20-projects/locals.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Derived values for the platform-projects stack. Computes the
#              per-role enable map, splits the reference set by home folder,
#              composes canonical project IDs, and reads the folder tree +
#              org outputs from remote state.
###############################################################################

locals {
  # From remote state.
  organization_id    = data.terraform_remote_state.org_baseline.outputs.organization_id
  organization_name  = data.terraform_remote_state.org_baseline.outputs.organization_name
  billing_account_id = data.terraform_remote_state.org_baseline.outputs.billing_account_id
  folder_ids         = data.terraform_remote_state.folders.outputs.folder_ids

  is_create = var.organization_mode == "create"
  is_read   = var.organization_mode == "existing"

  will_create = local.is_create && var.enable_platform_projects
  will_read   = local.is_read && var.enable_platform_projects

  # -----------------------------------------------------------------------------
  # Per-role enable flags — respected in both modes (existing mode filters
  # existing_project_ids so consumers cannot pull IDs for roles they disabled).
  # -----------------------------------------------------------------------------
  role_enabled = {
    plogs    = var.enable_plogs
    pmgm     = var.enable_pmgm
    piam     = var.enable_piam
    pdns     = var.enable_pdns
    pingress = var.enable_pingress
    sandbox  = var.enable_sandbox
  }

  # -----------------------------------------------------------------------------
  # Canonical project ID composition — mirrors the GCP LZ single-instance
  # pattern:
  #   ${org_prefix}-prj-${company}[-${division}]-<role_id_segment>-${control}
  # role_id_segment is the 'p'-prefixed form (piam, plogs, ..., psandbox).
  # -----------------------------------------------------------------------------
  id_segment_by_role = {
    plogs    = "plogs"
    pmgm     = "pmgm"
    piam     = "piam"
    pdns     = "pdns"
    pingress = "pingress"
    sandbox  = "psandbox"
  }

  reference_project_ids = {
    for role, seg in local.id_segment_by_role :
    role => join("-", compact([var.org_prefix, "prj", var.company, var.division, seg, var.control]))
    if local.role_enabled[role]
  }

  # -----------------------------------------------------------------------------
  # Split by home folder — the shared 'projects' module accepts one parent
  # per instantiation, so the stack calls it twice: Platform-folder set and
  # Sandbox-folder set.
  # -----------------------------------------------------------------------------
  platform_folder_roles = ["plogs", "pmgm", "piam", "pdns", "pingress"]
  sandbox_folder_roles  = ["sandbox"]

  # -----------------------------------------------------------------------------
  # Build the input map for each shared-module instantiation. Extra services
  # come from var.extra_services_by_role; the module already provides a
  # baseline set (compute, cloudresourcemanager, iam) via its own defaults.
  # -----------------------------------------------------------------------------
  platform_projects_input = {
    for role in local.platform_folder_roles :
    role => {
      project_id = local.reference_project_ids[role]
      services = concat(
        ["compute.googleapis.com", "cloudresourcemanager.googleapis.com", "iam.googleapis.com"],
        lookup(var.extra_services_by_role, role, [])
      )
      labels = {
        managed_by = "terraform"
        tier       = "0"
        role       = role
      }
    }
    if lookup(local.role_enabled, role, false) && contains(keys(local.reference_project_ids), role)
  }

  sandbox_projects_input = {
    for role in local.sandbox_folder_roles :
    role => {
      project_id = local.reference_project_ids[role]
      services = concat(
        ["compute.googleapis.com", "cloudresourcemanager.googleapis.com", "iam.googleapis.com"],
        lookup(var.extra_services_by_role, role, [])
      )
      labels = {
        managed_by = "terraform"
        tier       = "0"
        role       = role
      }
    }
    if lookup(local.role_enabled, role, false) && contains(keys(local.reference_project_ids), role)
  }

  # -----------------------------------------------------------------------------
  # Consolidated 'existing' mode map — filter to enabled roles only.
  # -----------------------------------------------------------------------------
  existing_ids_filtered = {
    for role, id in var.existing_project_ids :
    role => id if lookup(local.role_enabled, role, false)
  }
}
