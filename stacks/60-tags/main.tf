###############################################################################
# File:        stacks/60-tags/main.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Provisions Resource Manager tag keys and tag values at
#              Organization scope. Tag values can only exist under a
#              tag key; Terraform's dependency graph handles the ordering
#              via the parent reference on google_tags_tag_value.
###############################################################################

# ---------------------------------------------------------------------------
# Remote state — Organization id / name.
# ---------------------------------------------------------------------------

data "terraform_remote_state" "org_baseline" {
  backend = "gcs"
  config = {
    bucket = var.org_baseline_state_bucket
    prefix = var.org_baseline_state_prefix
  }
}

# ---------------------------------------------------------------------------
# Tag keys — one per entry in the merged catalog.
# ---------------------------------------------------------------------------

resource "google_tags_tag_key" "keys" {
  for_each = var.enable_tags ? local.all_tag_keys : {}

  parent      = local.organization_name
  short_name  = each.key
  description = each.value.description

  purpose      = "GCE_FIREWALL" # allows the tag to be used in hierarchical firewall policies
  purpose_data = {}             # empty for GCE_FIREWALL purpose
}

# ---------------------------------------------------------------------------
# Tag values — one per (key, value) pair. Parented to the tag key resource
# so Terraform's dependency graph ensures the key exists before the value.
# ---------------------------------------------------------------------------

resource "google_tags_tag_value" "values" {
  for_each = var.enable_tags ? local.all_tag_values : {}

  parent      = google_tags_tag_key.keys[each.value.key_name].name
  short_name  = each.value.value
  description = "Value '${each.value.value}' of tag key '${each.value.key_name}'. Managed by gcp-org-hierarchy/60-tags."
}

# ---------------------------------------------------------------------------
# Preconditions.
# ---------------------------------------------------------------------------

resource "null_resource" "preconditions" {
  count = var.enable_tags ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.organization_id != null && local.organization_id != ""
      error_message = "organization_id from 00-org-baseline is empty."
    }

    precondition {
      condition = alltrue([
        for k, _ in local.all_tag_keys : can(regex("^[a-z][a-z0-9-]{0,62}$", k))
      ])
      error_message = "Every tag key short_name must be lowercase, alphanumeric with hyphens, start with a letter, and be 1-63 chars."
    }

    precondition {
      condition = alltrue([
        for k, v in local.all_tag_values : can(regex("^[a-z0-9][a-z0-9_-]{0,62}$", v.value))
      ])
      error_message = "Every tag value short_name must be lowercase alphanumeric with hyphens or underscores, 1-63 chars."
    }
  }
}
