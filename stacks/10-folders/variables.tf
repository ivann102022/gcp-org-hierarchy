###############################################################################
# File:        stacks/10-folders/variables.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Inputs for the folders stack. Provisions or references the
#              folder tree using a flat map of folder-key → { display_name,
#              parent_key } so children can reference roots by Terraform's
#              dependency graph without nested-map recursion.
###############################################################################

# -----------------------------------------------------------------------------
# Global mode variable.
# -----------------------------------------------------------------------------

variable "organization_mode" {
  description = "Only 'existing' and 'create' are valid. See ADR-0001."
  type        = string
  default     = "existing"
  validation {
    condition     = contains(["existing", "create"], var.organization_mode)
    error_message = "organization_mode must be 'existing' or 'create'."
  }
}

# -----------------------------------------------------------------------------
# Remote-state pointer to 00-org-baseline (provides organization_id + name).
# -----------------------------------------------------------------------------

variable "org_baseline_state_bucket" {
  description = "GCS bucket that holds the remote state for stack 00-org-baseline. Same bucket the rest of the portfolio uses; prefix is fixed."
  type        = string
}

variable "org_baseline_state_prefix" {
  description = "Prefix under org_baseline_state_bucket where 00-org-baseline stored its state. Override only if you changed the default in that stack's backend.tf."
  type        = string
  default     = "gcp-org-hierarchy/00-org-baseline"
}

# -----------------------------------------------------------------------------
# Layer switches.
# -----------------------------------------------------------------------------

variable "enable_folders" {
  description = "Master switch. When false, this stack is a no-op and folder_ids output is an empty map."
  type        = bool
  default     = false
}

variable "create_reference_folder_tree" {
  description = "When true (and organization_mode = 'create'), provisions the reference folder set: Platform, LandingZones, Sandbox. Sub-folders under LandingZones are opt-in via reference_landing_zone_children."
  type        = bool
  default     = true
}

variable "reference_landing_zone_children" {
  description = "Opt-in sub-folders under LandingZones. Common set: ['Production', 'NonProduction']. Empty list means LandingZones has no default children (each LZ can add its own sub-folder later)."
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for name in var.reference_landing_zone_children : can(regex("^[A-Z][A-Za-z0-9]{0,29}$", name))
    ])
    error_message = "Each reference_landing_zone_children entry must be PascalCase, 1-30 alphanumeric characters."
  }
}

# -----------------------------------------------------------------------------
# Custom folders — flat map with parent reference.
# parent_key = "__org__" means the folder attaches directly to the Organization.
# parent_key = "<other folder key>" means it attaches to another folder in
# either reference_folder_tree or custom_folders itself.
# -----------------------------------------------------------------------------

variable "custom_folders" {
  description = "Additional folders beyond the reference tree. Flat map keyed by a stable folder key. parent_key = '__org__' or the key of another folder in the reference tree or this map."
  type = map(object({
    display_name = string
    parent_key   = string
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Existing folder IDs — required when organization_mode = 'existing' and
# downstream needs the folder_ids map populated. GCP does not offer a
# by-display-name folder lookup data source at organization scope, so IDs
# are provided explicitly.
# -----------------------------------------------------------------------------

variable "existing_folder_ids" {
  description = "Map of folder display name → folder resource name ('folders/<id>'). Only consumed when organization_mode = 'existing'. Keys should mirror the reference tree keys and any custom folder keys so downstream contract expectations hold."
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.existing_folder_ids : can(regex("^folders/[0-9]+$", v))
    ])
    error_message = "Every existing_folder_ids value must be of the form 'folders/<numeric_id>'."
  }
}
