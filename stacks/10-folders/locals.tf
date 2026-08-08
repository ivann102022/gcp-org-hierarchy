###############################################################################
# File:        stacks/10-folders/locals.tf
# Author:      Ismael Cruz
# Version:     0.2.0
# Description: Derived values for the folders stack. Computes the reference
#              tree at three depths (roots, children, grandchildren) with
#              composite keys for LandingZones env grandchildren so
#              HostPrj-PRO and ServicePrj-PRO can coexist in a flat map
#              without display-name collision.
###############################################################################

locals {
  # From remote state.
  organization_id   = data.terraform_remote_state.org_baseline.outputs.organization_id
  organization_name = data.terraform_remote_state.org_baseline.outputs.organization_name

  is_create = var.organization_mode == "create"
  is_read   = var.organization_mode == "existing"

  # -----------------------------------------------------------------------------
  # Depth 1 — reference roots at the Organization scope.
  # -----------------------------------------------------------------------------
  reference_roots = var.create_reference_folder_tree ? {
    Platform     = { display_name = "Platform", parent_key = "__org__" }
    LandingZones = { display_name = "LandingZones", parent_key = "__org__" }
    Sandbox      = { display_name = "Sandbox", parent_key = "__org__" }
  } : {}

  # -----------------------------------------------------------------------------
  # Depth 2 — reference children under Platform.
  # One folder per platform project (Logs / Management / IAM / DNS / Ingress
  # by default). See ADR-0005 for the 1:1 folder-per-platform-project decision.
  # -----------------------------------------------------------------------------
  reference_platform_children = var.create_reference_folder_tree ? {
    for name in var.reference_platform_children :
    name => { display_name = name, parent_key = "Platform" }
  } : {}

  # -----------------------------------------------------------------------------
  # Depth 2 — reference children under LandingZones.
  # Every entry from var.reference_landing_zone_children becomes a folder;
  # entries with has_environments = true also produce depth-3 grandchildren
  # (see local.reference_lz_env_grandchildren below).
  # -----------------------------------------------------------------------------
  reference_lz_children = var.create_reference_folder_tree ? {
    for name, _ in var.reference_landing_zone_children :
    name => { display_name = name, parent_key = "LandingZones" }
  } : {}

  # -----------------------------------------------------------------------------
  # Depth 3 — environment grandchildren under LandingZones children whose
  # has_environments = true. Composite key ('<parent>-<env>', e.g. 'HostPrj-PRO')
  # avoids display-name collision when PRO appears under multiple parents.
  # See ADR-0006 for the composite-key convention.
  # -----------------------------------------------------------------------------
  reference_lz_env_grandchildren = var.create_reference_folder_tree ? merge([
    for parent_name, parent_spec in var.reference_landing_zone_children : {
      for env in var.reference_landing_zone_environments :
      "${parent_name}-${env}" => {
        display_name = env
        parent_key   = parent_name
      }
      } if parent_spec.has_environments
  ]...) : {}

  # -----------------------------------------------------------------------------
  # Full merged map — depth 1 + depth 2 + depth 3 + operator-supplied custom.
  # -----------------------------------------------------------------------------
  all_folders = merge(
    local.reference_roots,
    local.reference_platform_children,
    local.reference_lz_children,
    local.reference_lz_env_grandchildren,
    var.custom_folders,
  )

  # -----------------------------------------------------------------------------
  # Depth-based split — one resource block per depth so Terraform's dependency
  # graph resolves parents before children. Depth is inferred from parent_key:
  #   __org__                             → root (depth 1)
  #   any root key                        → child (depth 2)
  #   any child key                       → grandchild (depth 3)
  #   any grandchild or custom key        → resolved via the graph
  # -----------------------------------------------------------------------------
  root_folder_keys       = keys(local.reference_roots)
  child_folder_keys      = concat(keys(local.reference_platform_children), keys(local.reference_lz_children))
  grandchild_folder_keys = keys(local.reference_lz_env_grandchildren)

  root_folders = {
    for k, v in local.all_folders : k => v if v.parent_key == "__org__"
  }

  child_folders = {
    for k, v in local.all_folders : k => v if contains(local.root_folder_keys, v.parent_key)
  }

  grandchild_folders = {
    for k, v in local.all_folders : k => v if contains(local.child_folder_keys, v.parent_key)
  }

  # Custom folders may attach at any depth; they are handled by the graph
  # because their parent_key resolves through the merged all_folders map.
  # Reserve for future: if a customer nests custom_folders 4+ deep, add a
  # google_folder.great_grandchildren block.

  will_create = local.is_create && var.enable_folders
  will_read   = local.is_read && var.enable_folders
}
