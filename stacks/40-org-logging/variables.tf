###############################################################################
# File:        stacks/40-org-logging/variables.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Inputs for the org-logging stack. Provisions
#              google_logging_organization_sink at Organization scope
#              routing every project's logs into the plogs project (from
#              Tier 0 20-projects), plus the IAM binding for the sink's
#              writer identity. See ADR-0003 and ADR-0012.
###############################################################################

# -----------------------------------------------------------------------------
# Remote-state pointers to 00-org-baseline + 20-projects.
# -----------------------------------------------------------------------------

variable "org_baseline_state_bucket" {
  description = "GCS bucket that holds the remote state for stack 00-org-baseline."
  type        = string
}

variable "org_baseline_state_prefix" {
  description = "Prefix under org_baseline_state_bucket."
  type        = string
  default     = "gcp-org-hierarchy/00-org-baseline"
}

variable "org_projects_state_bucket" {
  description = "GCS bucket that holds the remote state for stack 20-projects (provides plogs)."
  type        = string
}

variable "org_projects_state_prefix" {
  description = "Prefix under org_projects_state_bucket."
  type        = string
  default     = "gcp-org-hierarchy/20-projects"
}

# -----------------------------------------------------------------------------
# Layer switches.
# -----------------------------------------------------------------------------

variable "enable_org_sink" {
  description = "Master switch. When false, no organization-level sink is created."
  type        = bool
  default     = false
}

variable "create_writer_identity_binding" {
  description = "When true, grants the sink's writer identity roles/logging.bucketWriter on the destination log bucket in plogs. Default true. Set to false if gcp-observability-baseline is handling the binding via its deferred integration hook (during transitional periods)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Sink configuration.
# -----------------------------------------------------------------------------

variable "org_prefix" {
  description = "Organization prefix used to name the sink resource."
  type        = string
  default     = "gcp0"
}

variable "control" {
  description = "Instance control segment."
  type        = string
  default     = "01"
}

variable "sink_name" {
  description = "Short name segment for the sink: '${org_prefix}-orgsink-<sink_name>-${control}'."
  type        = string
  default     = "central"
}

variable "sink_filter" {
  description = "Cloud Logging filter that determines which log entries are exported. Empty (default) = all logs from every project under the Organization. Override for cost control: e.g. 'severity>=WARNING' to keep only warnings and errors, or specific resource type filters."
  type        = string
  default     = ""
}

variable "include_children" {
  description = "When true (default), the sink captures logs from every project in every folder under the Organization. When false, only the Org-scope logs. Almost always true — the whole point of an org sink is to aggregate."
  type        = bool
  default     = true
}

variable "disabled" {
  description = "When true, the sink exists but does not export. Useful for pause/resume scenarios (e.g. cost investigation) without deleting the sink or losing the writer identity."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Destination — defaults to the log bucket in plogs (from Tier 0). Override
# only when routing to BigQuery / Pub/Sub / GCS at the org sink level (rare;
# most deployments do that in gcp-observability-baseline's 10-log-exports).
# -----------------------------------------------------------------------------

variable "destination_type" {
  description = "Destination type for the org sink. Default 'log_bucket' routes to the log bucket in plogs. Alternatives: 'bigquery', 'pubsub', 'storage'. For most deployments, keep 'log_bucket' at the org level and use gcp-observability-baseline/10-log-exports for downstream exports."
  type        = string
  default     = "log_bucket"
  validation {
    condition     = contains(["log_bucket", "bigquery", "pubsub", "storage"], var.destination_type)
    error_message = "destination_type must be 'log_bucket', 'bigquery', 'pubsub', or 'storage'."
  }
}

variable "destination_log_bucket" {
  description = "When destination_type = 'log_bucket': name of the log bucket in plogs. Default '_Default' targets the standard project log bucket; override to a custom bucket name (e.g. one provisioned by gcp-observability-baseline/00-log-storage)."
  type        = string
  default     = "_Default"
}

variable "destination_log_bucket_location" {
  description = "Location of the destination log bucket. Default 'global'; override to a region (e.g. 'eu') for data-residency."
  type        = string
  default     = "global"
}

variable "destination_override" {
  description = "Full sink destination string when destination_type != 'log_bucket'. Format per GCP docs (e.g. 'bigquery.googleapis.com/projects/PLOGS/datasets/DS' or 'pubsub.googleapis.com/projects/PLOGS/topics/T' or 'storage.googleapis.com/BUCKET'). Empty when destination_type = 'log_bucket'."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Exclusions — sink-level exclusions filter out noise before it's exported.
# Different from project-level exclusions (which drop at ingest, before
# any sink). Sink exclusions are cheaper for cost management when you want
# some sinks to receive the data and others not.
# -----------------------------------------------------------------------------

variable "exclusions" {
  description = "Map of exclusion name → { description, filter, disabled }. Sink-level exclusions filter logs that would otherwise be exported by this sink. Common use: exclude high-volume health-check logs from the org sink while letting them stay in individual project buckets."
  type = map(object({
    description = string
    filter      = string
    disabled    = optional(bool, false)
  }))
  default = {}
}
