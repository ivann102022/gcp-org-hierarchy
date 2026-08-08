###############################################################################
# File:        stacks/50-org-iam/backend.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Remote state backend for the org-iam stack.
###############################################################################

terraform {
  backend "gcs" {
    bucket = "REPLACE-ME-tfstate-bucket"
    prefix = "gcp-org-hierarchy/50-org-iam"
  }
}
