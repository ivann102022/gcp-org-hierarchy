###############################################################################
# File:        stacks/20-projects/outputs.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Public contract of the platform-projects stack. Both modes
#              produce the same output shape (map keyed by role) so
#              downstream consumers stay agnostic to how the projects
#              arrived.
###############################################################################

output "platform_project_ids" {
  description = "Map of role → project ID. Reference roles: plogs, pmgm, piam, pdns, pingress, sandbox. Keys align with the GCP LZs' existing_project_ids input."
  value = local.will_create ? merge(
    try(module.platform_projects[0].project_ids, {}),
    try(module.sandbox_projects[0].project_ids, {}),
    ) : (
    local.will_read ? local.existing_ids_filtered : {}
  )
}

output "platform_project_numbers" {
  description = "Map of role → project number (string). Needed by IAM bindings and log destinations that reference project number rather than ID. Empty in 'existing' mode (project numbers can be looked up via a data source in the consumer if needed)."
  value = local.will_create ? merge(
    try(module.platform_projects[0].project_numbers, {}),
    try(module.sandbox_projects[0].project_numbers, {}),
  ) : {}
}

output "platform_project_names" {
  description = "Map of role → project display name."
  value = local.will_create ? merge(
    try(module.platform_projects[0].project_names, {}),
    try(module.sandbox_projects[0].project_names, {}),
  ) : {}
}

output "mode" {
  description = "Echoes organization_mode."
  value       = var.organization_mode
}
