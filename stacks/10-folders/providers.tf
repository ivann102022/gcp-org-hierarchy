###############################################################################
# File:        stacks/10-folders/providers.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Provider configuration for the folders stack. Executing
#              credentials must hold roles/resourcemanager.folderCreator at
#              the Organization scope when organization_mode = 'create'.
###############################################################################

provider "google" {}

provider "google-beta" {}
