###############################################################################
# File:        stacks/30-org-policies/backend.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Remote state backend for the org-policies stack.
###############################################################################

terraform {
  backend "gcs" {
    bucket = "REPLACE-ME-tfstate-bucket"
    prefix = "gcp-org-hierarchy/30-org-policies"
  }
}
