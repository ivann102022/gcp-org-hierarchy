###############################################################################
# File:        stacks/30-org-policies/providers.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Provider configuration for the org-policies stack. Executing
#              credentials must hold roles/orgpolicy.policyAdmin at the
#              Organization scope.
###############################################################################

provider "google" {}

provider "google-beta" {}
