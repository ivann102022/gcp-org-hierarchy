###############################################################################
# File:        stacks/40-org-logging/main.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Provisions the organization-level log sink (with include_children
#              = true so every project in every folder is captured) and grants
#              the sink's writer identity roles/logging.bucketWriter on the
#              destination log bucket in plogs. See ADR-0003 (why here, not
#              in obs-baseline) and ADR-0012 (design choices).
###############################################################################

# ---------------------------------------------------------------------------
# Remote state — org id + plogs project id.
# ---------------------------------------------------------------------------

data "terraform_remote_state" "org_baseline" {
  backend = "gcs"
  config = {
    bucket = var.org_baseline_state_bucket
    prefix = var.org_baseline_state_prefix
  }
}

data "terraform_remote_state" "org_projects" {
  backend = "gcs"
  config = {
    bucket = var.org_projects_state_bucket
    prefix = var.org_projects_state_prefix
  }
}

# ---------------------------------------------------------------------------
# The organization sink. unique_writer_identity = true so GCP mints a
# dedicated SA for this sink (visible as writer_identity output) — never
# reuse the default logging SA for org sinks (audit clarity).
# ---------------------------------------------------------------------------

resource "google_logging_organization_sink" "org" {
  count = var.enable_org_sink ? 1 : 0

  name             = local.sink_resource_name
  org_id           = local.organization_id
  destination      = local.destination
  filter           = var.sink_filter
  include_children = var.include_children
  disabled         = var.disabled

  description = "Organization-wide log sink routing every project's logs to ${var.destination_type} destination. Managed by gcp-org-hierarchy/40-org-logging."

  dynamic "exclusions" {
    for_each = var.exclusions
    content {
      name        = exclusions.key
      description = exclusions.value.description
      filter      = exclusions.value.filter
      disabled    = exclusions.value.disabled
    }
  }
}

# ---------------------------------------------------------------------------
# IAM binding: grant the sink's writer identity permission to write to the
# destination. For log_bucket destination, that's roles/logging.bucketWriter
# on the plogs project (bucket-level IAM is not required; project-scope role
# is sufficient and the industry pattern).
#
# gcp-observability-baseline/00-log-storage also has a deferred-integration
# hook that would create the same binding (with an IAM condition scoping to
# a specific bucket). When both stacks are applied, the bindings are
# idempotent at the API level (google_project_iam_member) — the effective
# policy has one binding for the same member+role. Two-state ownership is
# ugly but functionally safe.
#
# Set var.create_writer_identity_binding = false if obs-baseline handles it
# and you want a clean single-owner state.
# ---------------------------------------------------------------------------

resource "google_project_iam_member" "writer_identity" {
  count = var.enable_org_sink && var.create_writer_identity_binding && var.destination_type == "log_bucket" ? 1 : 0

  project = local.logs_project_id
  role    = "roles/logging.bucketWriter"
  member  = google_logging_organization_sink.org[0].writer_identity
}

# For non-log_bucket destinations, the writer identity needs different roles
# (bigquery.dataEditor for BQ, pubsub.publisher for Pub/Sub, storage.objectCreator
# for GCS). Those are typically handled in the destination-owning stack
# (obs-baseline/10-log-exports) because the destination lives there.

# ---------------------------------------------------------------------------
# Preconditions.
# ---------------------------------------------------------------------------

resource "null_resource" "preconditions" {
  count = var.enable_org_sink ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.organization_id != null && local.organization_id != ""
      error_message = "organization_id from 00-org-baseline is empty."
    }

    precondition {
      condition     = local.logs_project_id != null && local.logs_project_id != ""
      error_message = "plogs project ID from 20-projects is empty. Apply 20-projects with enable_plogs = true before this stack."
    }

    precondition {
      condition     = var.destination_type != "log_bucket" || var.destination_log_bucket != ""
      error_message = "destination_log_bucket must be set when destination_type = 'log_bucket'."
    }

    precondition {
      condition     = var.destination_type == "log_bucket" || var.destination_override != ""
      error_message = "destination_override must be set when destination_type is 'bigquery', 'pubsub', or 'storage'."
    }
  }
}
