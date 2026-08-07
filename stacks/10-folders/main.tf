###############################################################################
# File:        stacks/10-folders/main.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Provisions the folder tree in 'create' mode using a two-pass
#              root/child split so children reference their root parent
#              through Terraform's dependency graph. In 'existing' mode the
#              stack is read-only — folder IDs come from the operator via
#              var.existing_folder_ids.
###############################################################################

# ---------------------------------------------------------------------------
# Remote state — organization_id and organization_name from 00-org-baseline.
# ---------------------------------------------------------------------------

data "terraform_remote_state" "org_baseline" {
  backend = "gcs"
  config = {
    bucket = var.org_baseline_state_bucket
    prefix = var.org_baseline_state_prefix
  }
}

# ---------------------------------------------------------------------------
# create mode — provision folders. Two passes: roots first, children second.
# The child block references the root's .name (format 'folders/<id>')
# through the resource address so Terraform sequences correctly.
# ---------------------------------------------------------------------------

resource "google_folder" "roots" {
  for_each = local.will_create ? local.root_folders : {}

  display_name        = each.value.display_name
  parent              = local.organization_name
  deletion_protection = true
}

resource "google_folder" "children" {
  for_each = local.will_create ? local.child_folders : {}

  display_name        = each.value.display_name
  parent              = google_folder.roots[each.value.parent_key].name
  deletion_protection = true
}

# ---------------------------------------------------------------------------
# Cross-layer preconditions.
# ---------------------------------------------------------------------------

resource "null_resource" "preconditions" {
  count = var.enable_folders ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.organization_id != null && local.organization_id != ""
      error_message = "organization_id from 00-org-baseline is empty. Apply stack 00-org-baseline first, then re-run this stack."
    }

    precondition {
      condition = alltrue([
        for k, v in var.custom_folders :
        v.parent_key == "__org__" || contains(keys(local.reference_roots), v.parent_key) || contains(keys(local.reference_lz_children), v.parent_key) || contains(keys(var.custom_folders), v.parent_key)
      ])
      error_message = "Every custom_folders entry must have parent_key = '__org__' or the key of a folder declared in the reference tree or in custom_folders itself."
    }

    precondition {
      condition     = !local.will_create || var.create_reference_folder_tree || length(var.custom_folders) > 0
      error_message = "enable_folders = true in 'create' mode requires either create_reference_folder_tree = true or a non-empty custom_folders map."
    }

    precondition {
      condition     = !local.will_read || length(var.existing_folder_ids) > 0
      error_message = "enable_folders = true in 'existing' mode requires existing_folder_ids to be populated (map of display_name → 'folders/<id>')."
    }
  }
}
