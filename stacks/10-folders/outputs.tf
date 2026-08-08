###############################################################################
# File:        stacks/10-folders/outputs.tf
# Author:      Ismael Cruz
# Version:     0.2.0
# Description: Public contract of the folders stack. folder_ids is keyed by
#              folder key (which equals display_name for depth-1 and depth-2
#              folders, and is composite '<parent>-<env>' for depth-3
#              LandingZones environment grandchildren). Both modes produce
#              the same output shape.
###############################################################################

output "folder_ids" {
  description = "Map of folder key → folder resource name ('folders/<id>'). Depth-1 and depth-2 keys equal the display name (Platform, Logs, HostPrj, ...). Depth-3 LandingZones environment keys are composite ('HostPrj-PRO', 'ServicePrj-DEV', ...). In 'create' mode, merges roots + children + grandchildren from google_folder resources. In 'existing' mode, echoes var.existing_folder_ids. Empty when enable_folders = false."
  value = local.will_create ? merge(
    { for k, r in google_folder.roots : k => r.name },
    { for k, r in google_folder.children : k => r.name },
    { for k, r in google_folder.grandchildren : k => r.name },
    ) : (
    local.will_read ? var.existing_folder_ids : {}
  )
}

output "root_folder_ids" {
  description = "Subset of folder_ids restricted to root-level folders (direct children of the Organization: Platform, LandingZones, Sandbox). Convenience for consumers that only care about the top level."
  value = local.will_create ? {
    for k, r in google_folder.roots : k => r.name
    } : (
    local.will_read ? {
      for k, v in var.existing_folder_ids : k => v if contains(keys(local.reference_roots), k) || try(var.custom_folders[k].parent_key, "") == "__org__"
    } : {}
  )
}

output "platform_child_folder_ids" {
  description = "Subset of folder_ids restricted to Platform's direct children (Logs, Management, IAM, DNS, Ingress by default). Consumed by 20-projects to place each platform project in its 1:1 home folder."
  value = local.will_create ? {
    for k, r in google_folder.children : k => r.name if try(local.reference_platform_children[k], null) != null
  } : {}
}

output "landing_zone_env_folder_ids" {
  description = "Subset of folder_ids restricted to LandingZones environment grandchildren (HostPrj-PRO, HostPrj-PRE, HostPrj-DEV, ServicePrj-PRO, ServicePrj-PRE, ServicePrj-DEV by default). Consumed by Tier 2 LZs to place tenant host and service projects in the correct env sub-folder."
  value = local.will_create ? {
    for k, r in google_folder.grandchildren : k => r.name
  } : {}
}

output "mode" {
  description = "Echoes organization_mode."
  value       = var.organization_mode
}
