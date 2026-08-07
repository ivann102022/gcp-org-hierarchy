###############################################################################
# File:        stacks/10-folders/backend.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Remote state backend for the folders stack. Bucket is a
#              placeholder — override via `terraform init -backend-config=...`
#              or by editing the value below.
###############################################################################

terraform {
  backend "gcs" {
    bucket = "REPLACE-ME-tfstate-bucket"
    prefix = "gcp-org-hierarchy/10-folders"
  }
}
