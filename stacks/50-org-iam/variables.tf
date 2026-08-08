###############################################################################
# File:        stacks/50-org-iam/variables.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Inputs for the org-iam stack. Provisions
#              google_organization_iam_member bindings for the minimum set
#              of privileged roles that must exist at Organization scope
#              for the portfolio to function. Explicitly excludes Workforce
#              Identity Federation (see ADR-0004) and identity-baseline's
#              custom roles. Break-glass model documented in ADR-0013.
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

variable "enable_org_iam" {
  description = "Master switch. When false, no org-scope IAM bindings are provisioned."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Curated role bindings — each is a list of principals to grant the role to.
# Principals use GCP's canonical format:
#   'user:alice@example.com'
#   'group:platform-admins@example.com'
#   'serviceAccount:sa@project.iam.gserviceaccount.com'
#   'domain:example.com'   (rarely used; broad)
#
# Prefer groups over users for humans; the Google Groups membership is the
# actual admission control point.
# -----------------------------------------------------------------------------

variable "org_admins" {
  description = "Principals granted roles/resourcemanager.organizationAdmin — the most privileged role in GCP. Prefer a single break-glass group + a small group of platform admins. Do not grant to individual users if avoidable."
  type        = list(string)
  default     = []
}

variable "project_creators" {
  description = "Principals granted roles/resourcemanager.projectCreator at Org scope. Typically the Terraform SA(s) that run Tier 0 stack 20-projects and any LZ that has create_projects = true fallback."
  type        = list(string)
  default     = []
}

variable "security_admins" {
  description = "Principals granted roles/iam.securityAdmin at Org scope. Grants ability to modify IAM policies org-wide. Typically SecOps team."
  type        = list(string)
  default     = []
}

variable "logging_admins" {
  description = "Principals granted roles/logging.admin at Org scope. Typically the Terraform SA that runs stack 40-org-logging + any human that needs to modify sinks / exclusions."
  type        = list(string)
  default     = []
}

variable "orgpolicy_admins" {
  description = "Principals granted roles/orgpolicy.policyAdmin at Org scope. Typically the Terraform SA that runs stack 30-org-policies."
  type        = list(string)
  default     = []
}

variable "org_viewers" {
  description = "Principals granted roles/resourcemanager.organizationViewer at Org scope. Low-privilege read access — safe to grant broadly (auditors, on-call engineers who need visibility across the tree)."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Break-glass — a dedicated principal (typically a group with a single user
# in it, activated only during emergencies) that holds Org Admin. Separated
# from var.org_admins so an alert can fire specifically when break-glass is
# used. See ADR-0013.
# -----------------------------------------------------------------------------

variable "break_glass_principals" {
  description = "Principals granted roles/resourcemanager.organizationAdmin as break-glass. Typically a group like 'group:break-glass@example.com' whose membership is empty by default and populated only during emergencies (with a Slack / ticket audit trail). Log-based alert on activation lives in gcp-observability-baseline (not this stack)."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Custom bindings — for org-scope roles not in the curated set.
# -----------------------------------------------------------------------------

variable "custom_org_iam_bindings" {
  description = "Map of binding_key → { role, members }. For org-scope roles outside the curated set. binding_key is a stable identifier (state key); role is the full GCP role name; members is a list of principals."
  type = map(object({
    role    = string
    members = list(string)
  }))
  default = {}
}
