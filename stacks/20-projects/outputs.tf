###############################################################################
# File:        stacks/20-projects/outputs.tf
# Author:      Ismael Cruz
# Version:     0.2.0
# Description: Public contract of the platform-projects stack. Both modes
#              produce the same output shape (map keyed by role) so
#              downstream consumers stay agnostic to how the projects were
#              provisioned or referenced.
###############################################################################

output "platform_project_ids" {
  description = "Map of role → project ID. Reference roles: plogs, pmgm, piam, pdns, pingress, sandbox. Keys align with the GCP LZs' existing_project_ids input."
  value = local.will_create ? merge([
    for _, m in module.projects_per_folder : try(m.project_ids, {})
    ]...) : (
    local.will_read ? local.existing_ids_filtered : {}
  )
}

output "platform_project_numbers" {
  description = "Map of role → project number (string). Needed by IAM bindings and log destinations that reference project number rather than ID. Empty in 'existing' mode."
  value = local.will_create ? merge([
    for _, m in module.projects_per_folder : try(m.project_numbers, {})
  ]...) : {}
}

output "platform_project_names" {
  description = "Map of role → project display name."
  value = local.will_create ? merge([
    for _, m in module.projects_per_folder : try(m.project_names, {})
  ]...) : {}
}

output "platform_project_home_folders" {
  description = "Map of role → home folder key where each project lives (v0.2.0). Useful for downstream stacks that need to scope IAM bindings or route policies to the folder that owns a project."
  value = local.will_create || local.will_read ? {
    for role, _ in local.role_enabled :
    role => lookup(var.platform_project_home_folder, role, "__org__")
    if local.role_enabled[role]
  } : {}
}

output "mode" {
  description = "Echoes organization_mode."
  value       = var.organization_mode
}
