###############################################################################
# File:        stacks/60-tags/backend.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Remote state backend for the tags stack.
###############################################################################

terraform {
  backend "gcs" {
    bucket = "REPLACE-ME-tfstate-bucket"
    prefix = "gcp-org-hierarchy/60-tags"
  }
}
