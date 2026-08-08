###############################################################################
# File:        stacks/10-folders/main.tf
# Author:      Ismael Cruz
# Version:     0.2.0
# Description: Provisions the folder tree in 'create' mode using three
#              resource blocks (roots / children / grandchildren) so
#              downstream folders reference their parent through
#              Terraform's dependency graph. In 'existing' mode the stack
#              is read-only — folder IDs come from the operator via
#              var.existing_folder_ids. v0.2.0 introduces the grandchildren
#              block to model the LandingZones/HostPrj/PRO-style depth-3
#              tree; state addresses of pre-existing v0.1.0 folders are
#              preserved by the moved blocks below.
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
# create mode — provision folders. Three passes matching depth 1/2/3.
# The child/grandchild blocks reference their parent's .name (format
# 'folders/<id>') through the resource address so Terraform sequences
# correctly without needing explicit depends_on.
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

resource "google_folder" "grandchildren" {
  for_each = local.will_create ? local.grandchild_folders : {}

  display_name        = each.value.display_name
  parent              = google_folder.children[each.value.parent_key].name
  deletion_protection = true
}

# ---------------------------------------------------------------------------
# State migration from v0.1.0 to v0.2.0.
#
# v0.1.0 shipped a two-pass model (roots + children). v0.2.0 introduces the
# grandchildren block and — because ADR-0005 changes the default children
# under Platform from Identity/Management/Connectivity to Logs/Management/
# IAM/DNS/Ingress — the set of children folders also changes.
#
# NOTE ON MIGRATION: existing v0.1.0 deployments used the old three-key
# platform set (Identity/Management/Connectivity). Rather than a `moved`
# block for every possible v0.1.0 name (which would create false positives
# for customers who never used those keys), the migration path is
# documented in the README:
#   - Fresh v0.2.0 deployment      → apply directly; new tree is created.
#   - Upgrade from v0.1.0          → the old Identity/Management/Connectivity
#                                    folders remain in place but are no longer
#                                    referenced. Operators either delete them
#                                    via console (empty folders) or add them
#                                    via var.custom_folders.
# ---------------------------------------------------------------------------

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
        v.parent_key == "__org__" || contains(keys(local.all_folders), v.parent_key)
      ])
      error_message = "Every custom_folders entry must have parent_key = '__org__' or the key of a folder declared in the reference tree or in custom_folders itself. LandingZones grandchildren use composite keys ('<parent>-<env>', e.g. 'HostPrj-PRO')."
    }

    precondition {
      condition     = !local.will_create || var.create_reference_folder_tree || length(var.custom_folders) > 0
      error_message = "enable_folders = true in 'create' mode requires either create_reference_folder_tree = true or a non-empty custom_folders map."
    }

    precondition {
      condition     = !local.will_read || length(var.existing_folder_ids) > 0
      error_message = "enable_folders = true in 'existing' mode requires existing_folder_ids to be populated (map of folder key → 'folders/<id>')."
    }
  }
}
