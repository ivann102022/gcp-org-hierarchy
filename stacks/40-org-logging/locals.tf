###############################################################################
# File:        stacks/40-org-logging/locals.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Derived values for the org-logging stack. Composes the sink
#              destination string and resource name.
###############################################################################

locals {
  # From remote state.
  organization_id      = data.terraform_remote_state.org_baseline.outputs.organization_id
  organization_name    = data.terraform_remote_state.org_baseline.outputs.organization_name
  platform_project_ids = data.terraform_remote_state.org_projects.outputs.platform_project_ids
  logs_project_id      = local.platform_project_ids.plogs

  # Sink resource name — follows portfolio naming convention.
  sink_resource_name = join("-", [var.org_prefix, "orgsink", var.sink_name, var.control])

  # Destination string. For log_bucket, GCP requires the full path:
  #   logging.googleapis.com/projects/<plogs>/locations/<loc>/buckets/<bucket>
  # For other types, the operator provides destination_override directly.
  destination = var.destination_type == "log_bucket" ? "logging.googleapis.com/projects/${local.logs_project_id}/locations/${var.destination_log_bucket_location}/buckets/${var.destination_log_bucket}" : var.destination_override
}
