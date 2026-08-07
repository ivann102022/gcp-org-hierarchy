###############################################################################
# File:        stacks/00-org-baseline/versions.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Terraform and provider version constraints for the
#              org-baseline stack. Pins to the same provider majors used by
#              every other Tier 0 / Tier 1 / Tier 2 GCP repo in the portfolio.
###############################################################################

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.14"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.14"
    }
  }
}
