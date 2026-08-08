###############################################################################
# File:        stacks/50-org-iam/providers.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Provider configuration. Executing credentials must hold
#              roles/resourcemanager.organizationAdmin at the Organization
#              scope (this is the most privileged role in GCP — treat with
#              matching operational discipline).
###############################################################################

provider "google" {}

provider "google-beta" {}
