###############################################################################
# File:        stacks/40-org-logging/backend.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Remote state backend for the org-logging stack.
###############################################################################

terraform {
  backend "gcs" {
    bucket = "REPLACE-ME-tfstate-bucket"
    prefix = "gcp-org-hierarchy/40-org-logging"
  }
}
