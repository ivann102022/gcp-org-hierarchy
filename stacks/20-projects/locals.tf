###############################################################################
# File:        stacks/20-projects/locals.tf
# Author:      Ismael Cruz
# Version:     0.2.0
# Description: Derived values for the platform-projects stack. Composes
#              canonical project IDs and groups them by home folder so the
#              shared 'projects' module can be instantiated once per
#              distinct home folder via for_each.
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
  # Per-role enable flags — respected in both modes.
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
  #   ${org_prefix}-prj-${company}[-${division}]-<role>-${control}
  #
  # v0.2.0: every role uses its own name as the ID segment (no more
  # 'psandbox' special case) — aligned with the naming shown in the
  # network topology diagram (gcp0-prj-emp-sandbox-01).
  # -----------------------------------------------------------------------------
  reference_project_ids = {
    for role, enabled in local.role_enabled :
    role => join("-", compact([var.org_prefix, "prj", var.company, var.division, role, var.control]))
    if enabled
  }

  # -----------------------------------------------------------------------------
  # Build the input map for the shared 'projects' module (one entry per
  # enabled role). Extra services come from var.extra_services_by_role;
  # the module ships a baseline set (compute, cloudresourcemanager, iam).
  # -----------------------------------------------------------------------------
  enabled_role_inputs = {
    for role, id in local.reference_project_ids :
    role => {
      project_id = id
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
  }

  # -----------------------------------------------------------------------------
  # Group enabled projects by their home folder (v0.2.0 refactor). The
  # shared 'projects' module accepts a single parent per invocation, so
  # grouping produces one invocation per non-empty folder group.
  #
  # Per the default var.platform_project_home_folder mapping:
  #   Logs        → { plogs }
  #   Management  → { pmgm }
  #   IAM         → { piam }
  #   DNS         → { pdns }
  #   Ingress     → { pingress }
  #   Sandbox     → { sandbox }
  #
  # Every group has exactly one project by default — reflecting the 1:1
  # folder-per-project decision (ADR-0005). Overrides that place multiple
  # roles in one folder collapse into a single invocation with several
  # projects (e.g. collapsing to the v0.1.0 flat layout with everything
  # under Platform).
  # -----------------------------------------------------------------------------
  distinct_home_folders = distinct([
    for role, _ in local.enabled_role_inputs :
    lookup(var.platform_project_home_folder, role, "__org__")
  ])

  projects_by_folder = {
    for folder in local.distinct_home_folders :
    folder => {
      for role, input in local.enabled_role_inputs :
      role => input
      if lookup(var.platform_project_home_folder, role, "__org__") == folder
    }
  }

  # -----------------------------------------------------------------------------
  # Consolidated 'existing' mode map — filter to enabled roles only.
  # -----------------------------------------------------------------------------
  existing_ids_filtered = {
    for role, id in var.existing_project_ids :
    role => id if lookup(local.role_enabled, role, false)
  }
}
