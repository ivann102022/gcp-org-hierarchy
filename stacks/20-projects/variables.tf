###############################################################################
# File:        stacks/20-projects/variables.tf
# Author:      Ismael Cruz
# Version:     0.2.0
# Description: Inputs for the platform-projects stack. Provisions or
#              references the six reference platform projects (plogs, pmgm,
#              piam, pdns, pingress, sandbox). v0.2.0 places each project
#              in its 1:1 home sub-folder (Logs / Management / IAM / DNS /
#              Ingress under Platform, Sandbox as its own root) per
#              ADR-0005. Consumes the shared 'projects' module at v0.1.0.
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
# Remote-state pointers to 00-org-baseline and 10-folders.
# -----------------------------------------------------------------------------

variable "org_baseline_state_bucket" {
  description = "GCS bucket that holds the remote state for 00-org-baseline."
  type        = string
}

variable "org_baseline_state_prefix" {
  description = "Prefix under org_baseline_state_bucket where 00-org-baseline stored its state."
  type        = string
  default     = "gcp-org-hierarchy/00-org-baseline"
}

variable "folders_state_bucket" {
  description = "GCS bucket that holds the remote state for 10-folders. Same bucket as org_baseline_state_bucket in the reference deployment."
  type        = string
}

variable "folders_state_prefix" {
  description = "Prefix under folders_state_bucket where 10-folders stored its state."
  type        = string
  default     = "gcp-org-hierarchy/10-folders"
}

# -----------------------------------------------------------------------------
# Layer switches.
# -----------------------------------------------------------------------------

variable "enable_platform_projects" {
  description = "Master switch. When false, this stack is a no-op and platform_project_ids is an empty map."
  type        = bool
  default     = false
}

variable "create_reference_platform_projects" {
  description = "When true (and organization_mode = 'create'), provisions the six reference platform projects (plogs, pmgm, piam, pdns, pingress, sandbox)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Naming variables — mirror the GCP LZ convention so IDs align without
# operator intervention. Reference deployment produces IDs like:
#   gcp0-prj-emp-plogs-01
#   gcp0-prj-emp-pmgm-01
#   gcp0-prj-emp-piam-01
#   gcp0-prj-emp-pdns-01
#   gcp0-prj-emp-pingress-01
#   gcp0-prj-emp-sandbox-01
# -----------------------------------------------------------------------------

variable "org_prefix" {
  description = "Organisation prefix, first segment of every project ID (default 'gcp0'). Match the GCP LZ convention to align cross-tier."
  type        = string
  default     = "gcp0"
}

variable "company" {
  description = "Company segment of project IDs (default 'emp' — the anonymised reference)."
  type        = string
  default     = "emp"
}

variable "division" {
  description = "Optional division segment (compacted out when empty)."
  type        = string
  default     = ""
}

variable "control" {
  description = "Instance control segment, last of every project ID (default '01')."
  type        = string
  default     = "01"
}

# -----------------------------------------------------------------------------
# Per-project toggles for the reference set. All default true — flipping
# a single one lets the operator opt out of e.g. sandbox on a compliance-
# constrained deployment.
# -----------------------------------------------------------------------------

variable "enable_plogs" {
  description = "Provision the plogs project (centralized logs, org-sink destination)."
  type        = bool
  default     = true
}

variable "enable_pmgm" {
  description = "Provision the pmgm project (KMS central + management)."
  type        = bool
  default     = true
}

variable "enable_piam" {
  description = "Provision the piam project (identity foundation)."
  type        = bool
  default     = true
}

variable "enable_pdns" {
  description = "Provision the pdns project (Cloud DNS host)."
  type        = bool
  default     = true
}

variable "enable_pingress" {
  description = "Provision the pingress project (shared ingress baseline)."
  type        = bool
  default     = true
}

variable "enable_sandbox" {
  description = "Provision the sandbox project (single-instance, ID uses 'sandbox' segment)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Services (APIs) to enable per project. The shared 'projects' module has
# a sensible default; override here per role when a project needs a
# specific extra API up-front.
# -----------------------------------------------------------------------------

variable "extra_services_by_role" {
  description = "Map of project role → list of extra Service APIs to enable on top of the shared module's defaults. Roles: plogs, pmgm, piam, pdns, pingress, sandbox."
  type        = map(list(string))
  default = {
    plogs    = ["logging.googleapis.com", "bigquery.googleapis.com"]
    pmgm     = ["cloudkms.googleapis.com", "secretmanager.googleapis.com"]
    piam     = ["iam.googleapis.com", "cloudidentity.googleapis.com"]
    pdns     = ["dns.googleapis.com"]
    pingress = ["compute.googleapis.com"]
    sandbox  = []
  }
}

# -----------------------------------------------------------------------------
# Role → home-folder mapping (v0.2.0). Default reproduces the reference
# architecture diagram: each platform project lives in its 1:1 sub-folder
# under Platform (per ADR-0005), sandbox lives directly under the Sandbox
# root. Overriding this map is the mechanism to relocate a project — e.g.
# collapse to the v0.1.0 flat layout by pointing every role at "Platform"
# and setting reference_platform_children = [] on 10-folders.
#
# Values must be folder keys known to 10-folders' folder_ids output (either
# a reference folder or a custom_folders entry). Unknown folder keys cause
# fallback to the Organization root (project created at Org level, with a
# console warning at plan time via the precondition below).
# -----------------------------------------------------------------------------

variable "platform_project_home_folder" {
  description = "Map of role → folder key where each platform project should be placed. Default reproduces the reference architecture: 1:1 folder-per-project under Platform (Logs/Management/IAM/DNS/Ingress) + sandbox under Sandbox. Override for flat layout or custom folder placement."
  type        = map(string)
  default = {
    plogs    = "Logs"
    pmgm     = "Management"
    piam     = "IAM"
    pdns     = "DNS"
    pingress = "Ingress"
    sandbox  = "Sandbox"
  }
}

# -----------------------------------------------------------------------------
# Existing project IDs — required when organization_mode = 'existing' with
# enable_platform_projects = true.
# -----------------------------------------------------------------------------

variable "existing_project_ids" {
  description = "Map of role → project ID. Only consumed when organization_mode = 'existing'. Keys should be a subset of {plogs, pmgm, piam, pdns, pingress, sandbox}."
  type        = map(string)
  default     = {}
}
