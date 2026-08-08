###############################################################################
# File:        stacks/30-org-policies/variables.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Inputs for the org-policies stack. Provisions a curated
#              catalog of google_org_policy_policy at Organization scope.
#              Every policy defaults to dry_run = true — surfaces violations
#              in the audit log without blocking. Operators flip individual
#              policies to enforce after review. See ADR-0011.
###############################################################################

# -----------------------------------------------------------------------------
# Remote-state pointer to 00-org-baseline (provides organization_id + name).
# -----------------------------------------------------------------------------

variable "org_baseline_state_bucket" {
  description = "GCS bucket that holds the remote state for stack 00-org-baseline."
  type        = string
}

variable "org_baseline_state_prefix" {
  description = "Prefix under org_baseline_state_bucket where 00-org-baseline stored its state."
  type        = string
  default     = "gcp-org-hierarchy/00-org-baseline"
}

# -----------------------------------------------------------------------------
# Layer switches.
# -----------------------------------------------------------------------------

variable "enable_org_policies" {
  description = "Master switch. When false, this stack is a no-op — no org policies are provisioned."
  type        = bool
  default     = false
}

variable "default_dry_run" {
  description = "Default value for the dry_run flag on every catalog policy. Defaults to true (audit-only). Set to false ONLY if you understand the enforcement implications org-wide. Individual policies override via var.enforce_overrides."
  type        = bool
  default     = true
}

variable "enforce_overrides" {
  description = "Per-policy override for the dry_run flag. Map of catalog key (see enable_* variables below) to a boolean: true = enforce (dry_run=false), false = keep in dry-run. Use this to promote individual policies to enforce as they're validated. Any policy not present in the map inherits var.default_dry_run."
  type        = map(bool)
  default     = {}
}

# -----------------------------------------------------------------------------
# Curated catalog — each policy has its own enable switch (default false).
# All 8 catalog policies default OFF; operator opts in one by one. When
# enabled, defaults to dry_run per var.default_dry_run.
# -----------------------------------------------------------------------------

variable "enable_disable_sa_keys" {
  description = "Enable constraints/iam.disableServiceAccountKeyCreation — deny creation of user-managed SA keys. Forces Workload Identity Federation / short-lived credentials. High signal, low false-positive rate."
  type        = bool
  default     = false
}

variable "enable_require_oslogin" {
  description = "Enable constraints/compute.requireOsLogin — forces OS Login for all VMs (auditable SSH via IAM instead of project-wide SSH keys)."
  type        = bool
  default     = false
}

variable "enable_deny_external_ip" {
  description = "Enable constraints/compute.vmExternalIpAccess = deny all — VMs cannot have public IPs. Forces Cloud NAT for egress, IAP tunnel for admin access."
  type        = bool
  default     = false
}

variable "enable_prevent_public_storage" {
  description = "Enable constraints/storage.publicAccessPrevention — GCS buckets cannot be made public. Blocks the classic 'public bucket' data exposure."
  type        = bool
  default     = false
}

variable "enable_restrict_sql_public_ip" {
  description = "Enable constraints/sql.restrictPublicIp — Cloud SQL instances cannot have public IPs. Forces private connectivity."
  type        = bool
  default     = false
}

variable "enable_allowed_policy_member_domains" {
  description = "Enable constraints/iam.allowedPolicyMemberDomains — restrict IAM member domains to a Workspace customer ID allow-list. Blocks cross-tenant IAM leaks. Requires var.allowed_customer_ids to be non-empty."
  type        = bool
  default     = false
}

variable "allowed_customer_ids" {
  description = "Workspace customer IDs allowed as IAM members when enable_allowed_policy_member_domains = true. Get via `gcloud organizations list` — the DIRECTORY_CUSTOMER_ID column."
  type        = list(string)
  default     = []
}

variable "enable_trusted_image_projects" {
  description = "Enable constraints/compute.trustedImageProjects — restrict VM boot disk images to a project allow-list. Requires var.trusted_image_projects to be non-empty."
  type        = bool
  default     = false
}

variable "trusted_image_projects" {
  description = "GCP projects allowed as sources of VM boot disk images when enable_trusted_image_projects = true. Format: 'projects/<id>'. Common: ['projects/debian-cloud', 'projects/cos-cloud', 'projects/ubuntu-os-cloud'] plus your custom golden-image projects."
  type        = list(string)
  default     = []
}

variable "enable_resource_locations" {
  description = "Enable constraints/gcp.resourceLocations — restrict resource creation to allowed locations. Requires var.allowed_locations to be non-empty."
  type        = bool
  default     = false
}

variable "allowed_locations" {
  description = "Location values allowed when enable_resource_locations = true. Accepts specific regions (e.g. 'europe-west1'), multi-regions ('eu', 'us'), and location groups ('in:eu-locations', 'in:us-locations'). Default assumes EU-only workloads."
  type        = list(string)
  default     = ["in:eu-locations"]
}

# -----------------------------------------------------------------------------
# Custom org policies — for constraints not in the curated catalog.
# -----------------------------------------------------------------------------

variable "custom_org_policies" {
  description = "Map of custom org policy name → policy spec. Use for constraints outside the curated catalog. See docs/adr/0011 for the discipline expected on custom entries."
  type = map(object({
    constraint = string
    rules = list(object({
      enforce           = optional(bool)
      allow_all         = optional(bool)
      deny_all          = optional(bool)
      values_allowed    = optional(list(string), [])
      values_denied     = optional(list(string), [])
      condition_title   = optional(string)
      condition_expr    = optional(string)
    }))
    dry_run = optional(bool, true)
  }))
  default = {}
}
