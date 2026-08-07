###############################################################################
# File:        stacks/10-folders/locals.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Derived values for the folders stack. Computes the reference
#              tree from the enable switches, splits folders into roots vs
#              children by parent_key, and merges custom folders in.
###############################################################################

locals {
  # From remote state.
  organization_id   = data.terraform_remote_state.org_baseline.outputs.organization_id
  organization_name = data.terraform_remote_state.org_baseline.outputs.organization_name

  is_create = var.organization_mode == "create"
  is_read   = var.organization_mode == "existing"

  # -----------------------------------------------------------------------------
  # Reference tree — three roots at the Organization scope.
  # -----------------------------------------------------------------------------
  reference_roots = var.create_reference_folder_tree ? {
    Platform     = { display_name = "Platform", parent_key = "__org__" }
    LandingZones = { display_name = "LandingZones", parent_key = "__org__" }
    Sandbox      = { display_name = "Sandbox", parent_key = "__org__" }
  } : {}

  # -----------------------------------------------------------------------------
  # Reference children under LandingZones — opt-in.
  # -----------------------------------------------------------------------------
  reference_lz_children = var.create_reference_folder_tree ? {
    for name in var.reference_landing_zone_children :
    name => { display_name = name, parent_key = "LandingZones" }
  } : {}

  # -----------------------------------------------------------------------------
  # Full merged map — reference + custom.
  # -----------------------------------------------------------------------------
  all_folders = merge(local.reference_roots, local.reference_lz_children, var.custom_folders)

  # -----------------------------------------------------------------------------
  # Two-pass split: roots (parent = __org__) vs children (parent = folder key).
  # Terraform's dependency graph resolves children referencing roots via
  # google_folder.roots[each.value.parent_key].name.
  # -----------------------------------------------------------------------------
  root_folders = {
    for k, v in local.all_folders : k => v if v.parent_key == "__org__"
  }

  child_folders = {
    for k, v in local.all_folders : k => v if v.parent_key != "__org__"
  }

  will_create = local.is_create && var.enable_folders
  will_read   = local.is_read && var.enable_folders
}
