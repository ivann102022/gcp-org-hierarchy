###############################################################################
# File:        stacks/60-tags/providers.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Provider configuration. Executing credentials must hold
#              roles/resourcemanager.tagAdmin at the Organization scope.
###############################################################################

provider "google" {}

provider "google-beta" {}
