###############################################################################
# File:        stacks/40-org-logging/providers.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Provider configuration for the org-logging stack. Executing
#              credentials must hold roles/logging.configWriter at the
#              Organization scope and roles/resourcemanager.projectIamAdmin
#              on the plogs project (for the writer-identity IAM binding).
###############################################################################

provider "google" {}

provider "google-beta" {}
