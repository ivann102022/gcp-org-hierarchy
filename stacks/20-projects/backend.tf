###############################################################################
# File:        stacks/20-projects/backend.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Remote state backend for the platform-projects stack.
###############################################################################

terraform {
  backend "gcs" {
    bucket = "REPLACE-ME-tfstate-bucket"
    prefix = "gcp-org-hierarchy/20-projects"
  }
}
