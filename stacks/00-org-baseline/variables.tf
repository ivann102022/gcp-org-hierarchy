###############################################################################
# File:        stacks/00-org-baseline/variables.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Inputs for the org-baseline stack. Locates the GCP
#              Organization by domain (never creates it — the Organization
#              is a Google Workspace / Cloud Identity artefact) and
#              optionally provisions essential contacts at the Org scope.
###############################################################################

# -----------------------------------------------------------------------------
# Global mode variable — every Tier 0 stack honours this.
# -----------------------------------------------------------------------------

variable "organization_mode" {
  description = "Reserved for future modes; only 'existing' and 'create' are valid in v0.1.0. See ADR-0001."
  type        = string
  default     = "existing"
  validation {
    condition     = contains(["existing", "create"], var.organization_mode)
    error_message = "organization_mode must be 'existing' or 'create'."
  }
}

# -----------------------------------------------------------------------------
# REQUIRED — Organization identification.
# -----------------------------------------------------------------------------

variable "organization_domain" {
  description = "Primary domain of the GCP Organization (e.g. 'example.com'). Used to look up the Organization via data source."
  type        = string
  validation {
    condition     = length(var.organization_domain) > 0 && can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.organization_domain))
    error_message = "organization_domain must be a valid lowercase domain (e.g. 'example.com')."
  }
}

variable "billing_account_id" {
  description = "Billing account ID (format 'XXXXXX-XXXXXX-XXXXXX') that platform projects created by stack 20-projects will attach to. Exposed via the contract for downstream consumers that need to link additional projects."
  type        = string
  validation {
    condition     = can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account_id))
    error_message = "billing_account_id must match the pattern XXXXXX-XXXXXX-XXXXXX (hex, uppercase)."
  }
}

# -----------------------------------------------------------------------------
# OPTIONAL — Essential contacts at the Organization scope.
# When enabled, requires roles/essentialcontacts.admin at the Org level.
# -----------------------------------------------------------------------------

variable "enable_essential_contacts" {
  description = "When true, provisions google_essential_contacts_contact resources at the Organization scope for the categories listed in var.essential_contacts."
  type        = bool
  default     = false
}

variable "essential_contacts" {
  description = "Map of email address → list of notification categories the contact should receive. Categories: ALL / SUSPENSION / SECURITY / TECHNICAL / BILLING / LEGAL / PRODUCT_UPDATES / TECHNICAL_INCIDENTS. Only consumed when enable_essential_contacts = true."
  type        = map(list(string))
  default     = {}
  validation {
    condition = alltrue([
      for _, categories in var.essential_contacts : alltrue([
        for c in categories : contains(
          ["ALL", "SUSPENSION", "SECURITY", "TECHNICAL", "BILLING", "LEGAL", "PRODUCT_UPDATES", "TECHNICAL_INCIDENTS"],
          c
        )
      ])
    ])
    error_message = "Every category in essential_contacts must be one of ALL / SUSPENSION / SECURITY / TECHNICAL / BILLING / LEGAL / PRODUCT_UPDATES / TECHNICAL_INCIDENTS."
  }
}

variable "essential_contact_language" {
  description = "Language tag (BCP-47) for the essential contacts. Google delivers notifications in this language when available."
  type        = string
  default     = "en"
}
