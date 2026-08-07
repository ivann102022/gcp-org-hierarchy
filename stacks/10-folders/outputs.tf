###############################################################################
# File:        stacks/10-folders/outputs.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Public contract of the folders stack. folder_ids is keyed by
#              display name and works identically in both modes.
###############################################################################

output "folder_ids" {
  description = "Map of folder display name → folder resource name ('folders/<id>'). In 'create' mode, populated from google_folder resources. In 'existing' mode, echoes var.existing_folder_ids. Empty when enable_folders = false."
  value = local.will_create ? merge(
    { for k, r in google_folder.roots : r.display_name => r.name },
    { for k, r in google_folder.children : r.display_name => r.name },
    ) : (
    local.will_read ? var.existing_folder_ids : {}
  )
}

output "root_folder_ids" {
  description = "Subset of folder_ids restricted to root-level folders (direct children of the Organization). Convenience for consumers that only care about top-level folders."
  value = local.will_create ? {
    for k, r in google_folder.roots : r.display_name => r.name
    } : (
    local.will_read ? {
      for k, v in var.existing_folder_ids : k => v if contains(keys(local.reference_roots), k) || try(var.custom_folders[k].parent_key, "") == "__org__"
    } : {}
  )
}

output "mode" {
  description = "Echoes organization_mode."
  value       = var.organization_mode
}
