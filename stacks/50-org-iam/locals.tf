###############################################################################
# File:        stacks/50-org-iam/locals.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Derived values for the org-iam stack. Flattens the curated
#              role bindings into a single map keyed by (role, member) for
#              google_organization_iam_member for_each.
###############################################################################

locals {
  # From remote state.
  organization_id = data.terraform_remote_state.org_baseline.outputs.organization_id

  # -----------------------------------------------------------------------------
  # Curated role map — role → list of members from the corresponding variable.
  # -----------------------------------------------------------------------------
  curated_role_members = {
    "roles/resourcemanager.organizationAdmin"  = concat(var.org_admins, var.break_glass_principals)
    "roles/resourcemanager.projectCreator"      = var.project_creators
    "roles/iam.securityAdmin"                   = var.security_admins
    "roles/logging.admin"                       = var.logging_admins
    "roles/orgpolicy.policyAdmin"               = var.orgpolicy_admins
    "roles/resourcemanager.organizationViewer"  = var.org_viewers
  }

  # -----------------------------------------------------------------------------
  # Flatten into (role, member) tuples so google_organization_iam_member's
  # for_each can iterate. Key is 'role|member' — stable across applies.
  # -----------------------------------------------------------------------------
  curated_bindings = merge([
    for role, members in local.curated_role_members : {
      for member in members :
      "${role}|${member}" => {
        role   = role
        member = member
      }
    }
  ]...)

  # -----------------------------------------------------------------------------
  # Custom bindings — flatten similarly.
  # -----------------------------------------------------------------------------
  custom_bindings = merge([
    for key, spec in var.custom_org_iam_bindings : {
      for member in spec.members :
      "${key}|${member}" => {
        role   = spec.role
        member = member
      }
    }
  ]...)

  # -----------------------------------------------------------------------------
  # Break-glass flag: exposed as output so consumers (obs-baseline alert
  # policies) can precondition their alerts on the break-glass principals
  # being populated.
  # -----------------------------------------------------------------------------
  break_glass_configured = length(var.break_glass_principals) > 0
}
