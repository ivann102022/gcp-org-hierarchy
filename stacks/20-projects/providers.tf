###############################################################################
# File:        stacks/20-projects/providers.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Provider configuration for the platform-projects stack.
#              Executing credentials must hold roles/resourcemanager.projectCreator
#              at the parent folder scope and roles/billing.user on the
#              billing account when organization_mode = 'create'.
###############################################################################

provider "google" {}

provider "google-beta" {}
