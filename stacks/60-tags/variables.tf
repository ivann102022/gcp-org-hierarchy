###############################################################################
# File:        stacks/60-tags/variables.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Inputs for the tags stack. Provisions Resource Manager tag
#              keys and tag values at Organization scope for cross-tier
#              governance. Opt-in by default (see ADR-0014).
###############################################################################

# -----------------------------------------------------------------------------
# Remote-state pointer to 00-org-baseline.
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

# -----------------------------------------------------------------------------
# Layer switches.
# -----------------------------------------------------------------------------

variable "enable_tags" {
  description = "Master switch. When false, no tags are provisioned. Default false — tagging is opt-in because it introduces ongoing operational cost (per-resource tagging discipline)."
  type        = bool
  default     = false
}

variable "create_reference_tag_set" {
  description = "When true (and enable_tags = true), provisions the reference tag catalog (environment, data-classification, cost-center, owner). Default true when the stack is enabled."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Reference tag catalog. Each entry:
#   - name        — tag key name (short, lowercase, hyphen-separated)
#   - description — human-readable purpose
#   - values      — list of allowed values (also lowercase, hyphen-separated)
#   - purpose     — governance vs cost vs compliance vs technical
# -----------------------------------------------------------------------------

variable "reference_environment_values" {
  description = "Values for the 'environment' tag key. Default matches the folder tree env split (prod / preprod / dev), lowercase per GCP tag convention."
  type        = list(string)
  default     = ["prod", "preprod", "dev"]
}

variable "reference_data_classification_values" {
  description = "Values for the 'data-classification' tag key. Default: 4-tier data classification (public / internal / confidential / restricted). Adjust to match customer's own scheme."
  type        = list(string)
  default     = ["public", "internal", "confidential", "restricted"]
}

variable "enable_cost_center_tag" {
  description = "Whether to provision the 'cost-center' tag key. Value list is free-form (no reference values shipped)."
  type        = bool
  default     = true
}

variable "enable_owner_tag" {
  description = "Whether to provision the 'owner' tag key. Value list is free-form (no reference values shipped)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Custom tag keys — arbitrary additions outside the reference set.
# -----------------------------------------------------------------------------

variable "custom_tag_keys" {
  description = "Map of tag key short_name → { description, values }. values is a list of allowed values; if empty, the tag key has no values (which is valid but rare — usually you want to constrain values)."
  type = map(object({
    description = string
    values      = list(string)
  }))
  default = {}
}
