###############################################################################
# File:        stacks/40-org-logging/outputs.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Public contract of the org-logging stack.
###############################################################################

output "log_sink_id" {
  description = "Organization sink resource name (e.g. 'organizations/<org_id>/sinks/<sink_name>'). Empty when enable_org_sink = false."
  value       = try(google_logging_organization_sink.org[0].id, "")
}

output "log_sink_name" {
  description = "Bare sink name."
  value       = try(google_logging_organization_sink.org[0].name, "")
}

output "log_sink_writer_identity" {
  description = "Service account identity that the sink writes as (format 'serviceAccount:...'). Consumed by gcp-observability-baseline via var.org_sink_writer_identity so it can grant the SA appropriate roles on downstream destinations."
  value       = try(google_logging_organization_sink.org[0].writer_identity, "")
}

output "log_sink_destination" {
  description = "Full destination string of the sink."
  value       = try(google_logging_organization_sink.org[0].destination, "")
}

output "log_sink_include_children" {
  description = "Echo of the include_children flag — whether the sink captures every project in every folder (true, default) or only Org-scope logs (false)."
  value       = var.include_children
}

output "log_sink_filter" {
  description = "Echo of the filter applied to the sink."
  value       = var.sink_filter
}
