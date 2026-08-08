###############################################################################
# File:        stacks/10-folders/variables.tf
# Author:      Ismael Cruz
# Version:     0.2.0
# Description: Inputs for the folders stack. Provisions or references the
#              folder tree using a flat map of folder-key → { display_name,
#              parent_key } so children can reference roots by Terraform's
#              dependency graph without nested-map recursion. v0.2.0 extends
#              to depth 3 (Organization → root → 1st-level child → 2nd-level
#              child) to model the reference tree in the architecture
#              diagrams: five 1:1 folders under Platform (Logs, Management,
#              IAM, DNS, Ingress), three folders under LandingZones (HUB
#              flat + HostPrj / ServicePrj with per-environment sub-folders),
#              Sandbox flat.
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
  description = "When true (and organization_mode = 'create'), provisions the reference folder set (see ADR-0005 and ADR-0006): Platform with five 1:1 sub-folders (Logs / Management / IAM / DNS / Ingress), LandingZones with HUB (flat) + HostPrj and ServicePrj (each with per-environment children), Sandbox (flat). Sub-folder sets are configurable via reference_platform_children, reference_landing_zone_children, and reference_landing_zone_environments."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Platform sub-folders — one per platform project (1:1 mapping, see ADR-0005).
# Default reproduces the reference architecture diagram: Logs / Management /
# IAM / DNS / Ingress. Each folder is the home of exactly one platform
# project provisioned by 20-projects.
# -----------------------------------------------------------------------------

variable "reference_platform_children" {
  description = "Sub-folders under the Platform root. Default reproduces the reference architecture: one folder per platform project (Logs, Management, IAM, DNS, Ingress). Empty list means Platform has no default children — every platform project falls back to sitting under Platform directly (flat layout). See ADR-0005 for why 1:1 folder-per-project."
  type        = list(string)
  default     = ["Logs", "Management", "IAM", "DNS", "Ingress"]
  validation {
    condition = alltrue([
      for name in var.reference_platform_children : can(regex("^[A-Z][A-Za-z0-9-]{0,29}$", name))
    ])
    error_message = "Each reference_platform_children entry must start with an uppercase letter, be 1-30 chars, and contain only letters / digits / hyphens."
  }
}

# -----------------------------------------------------------------------------
# LandingZones sub-folders — split between "flat" (single project directly
# inside) and "env-split" (per-environment sub-folders inside). See ADR-0006.
# Default reproduces the reference architecture:
#   HUB          → flat (single shared hub project across environments)
#   HostPrj      → env-split (one host project per environment)
#   ServicePrj   → env-split (Shared VPC service projects per environment)
# -----------------------------------------------------------------------------

variable "reference_landing_zone_children" {
  description = "Sub-folders under the LandingZones root. Each entry declares whether it has per-environment sub-folders. Default: HUB flat (no envs) + HostPrj and ServicePrj env-split. See ADR-0006 for the HostPrj/ServicePrj lifecycle split rationale."
  type = map(object({
    has_environments = bool
  }))
  default = {
    HUB        = { has_environments = false }
    HostPrj    = { has_environments = true }
    ServicePrj = { has_environments = true }
  }
  validation {
    condition = alltrue([
      for name, _ in var.reference_landing_zone_children : can(regex("^[A-Z][A-Za-z0-9-]{0,29}$", name))
    ])
    error_message = "Each reference_landing_zone_children key must start with an uppercase letter, be 1-30 chars, and contain only letters / digits / hyphens."
  }
}

# -----------------------------------------------------------------------------
# Environment sub-folders — used for every LandingZones child that has
# has_environments = true. All english for consistency (matches PRO/PRE/DEV
# in the GCP LZ codebases).
# -----------------------------------------------------------------------------

variable "reference_landing_zone_environments" {
  description = "Environment sub-folder names, applied under every LandingZones child whose has_environments = true. Default ['PRO', 'PRE', 'DEV'] matches the shipped GCP LZs. Override for customers with more (STG, QA) or fewer (PRO+DEV only) environments."
  type        = list(string)
  default     = ["PRO", "PRE", "DEV"]
  validation {
    condition = alltrue([
      for name in var.reference_landing_zone_environments : can(regex("^[A-Z][A-Za-z0-9-]{0,29}$", name))
    ])
    error_message = "Each reference_landing_zone_environments entry must start with an uppercase letter, be 1-30 chars, and contain only letters / digits / hyphens."
  }
}

# -----------------------------------------------------------------------------
# Custom folders — flat map with parent reference.
# parent_key = "__org__"                    → attaches to the Organization.
# parent_key = "<reference root>"           → attaches to Platform / LandingZones / Sandbox.
# parent_key = "<reference platform child>" → attaches to Logs / Management / IAM / DNS / Ingress.
# parent_key = "<reference lz child>"       → attaches to HUB / HostPrj / ServicePrj.
# parent_key = "<lz env grandchild key>"    → attaches to HostPrj-PRO / ServicePrj-DEV / etc.
#                                             (composite keys — see docs for the convention)
# parent_key = "<other custom_folders key>" → attaches to any folder in this map.
# -----------------------------------------------------------------------------

variable "custom_folders" {
  description = "Additional folders beyond the reference tree. Flat map keyed by a stable folder key. parent_key = '__org__' or the key of any folder declared in the reference tree (roots / children / grandchildren) or this map. LandingZones grandchildren keys are composite: '<parent>-<env>' (e.g. 'HostPrj-PRO'). See docs/adr/0006 for the composite-key convention."
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
# are provided explicitly. Keys must mirror the reference tree keys and any
# custom folder keys (including composite keys for LandingZones grandchildren).
# -----------------------------------------------------------------------------

variable "existing_folder_ids" {
  description = "Map of folder key → folder resource name ('folders/<id>'). Only consumed when organization_mode = 'existing'. Keys must mirror the reference tree keys (Platform, LandingZones, Sandbox, Logs, Management, IAM, DNS, Ingress, HUB, HostPrj, ServicePrj, HostPrj-PRO, HostPrj-PRE, HostPrj-DEV, ServicePrj-PRO, ServicePrj-PRE, ServicePrj-DEV) and any custom folder keys so downstream contract expectations hold."
  type        = map(string)
  default     = {}
  validation {
    condition = alltrue([
      for k, v in var.existing_folder_ids : can(regex("^folders/[0-9]+$", v))
    ])
    error_message = "Every existing_folder_ids value must be of the form 'folders/<numeric_id>'."
  }
}
