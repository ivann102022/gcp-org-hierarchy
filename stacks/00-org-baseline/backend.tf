###############################################################################
# File:        stacks/00-org-baseline/backend.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Remote state backend for the org-baseline stack. Bucket is a
#              placeholder — override via `terraform init -backend-config=...`
#              or by editing the value below to match your organisation's
#              state bucket (created by scripts/bootstrap-tfstate.sh).
#              State is NEVER stored locally in this project.
###############################################################################

terraform {
  backend "gcs" {
    bucket = "REPLACE-ME-tfstate-bucket"
    prefix = "gcp-org-hierarchy/00-org-baseline"
  }
}
