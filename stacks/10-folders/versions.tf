###############################################################################
# File:        stacks/10-folders/versions.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Terraform and provider version constraints for the folders
#              stack.
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
