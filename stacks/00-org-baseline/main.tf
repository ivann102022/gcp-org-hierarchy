###############################################################################
# File:        stacks/00-org-baseline/main.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: References the GCP Organization by domain (never creates it —
#              see ADR-0001) and optionally provisions essential contacts
#              at the Organization scope. This is the anchor stack that
#              every downstream Tier 0 stack, every Tier 1 baseline, and
#              every Tier 2 LZ can look up for the canonical organization_id.
###############################################################################

# ------------------------------------------------------------------------------
# The Organization itself — always a data source (both modes).
# In GCP the Organization is a Google Workspace / Cloud Identity artefact and
# cannot be created via Terraform. The 'create' mode of Tier 0 refers to
# folders and projects, not the Organization itself.
# ------------------------------------------------------------------------------

data "google_organization" "this" {
  domain = var.organization_domain
}

# ------------------------------------------------------------------------------
# Essential contacts — opt-in.
# Requires roles/essentialcontacts.admin at the Organization scope.
# ------------------------------------------------------------------------------

resource "google_essential_contacts_contact" "org" {
  for_each = var.enable_essential_contacts ? var.essential_contacts : {}

  parent                              = local.organization_name
  email                               = each.key
  language_tag                        = var.essential_contact_language
  notification_category_subscriptions = each.value
}
