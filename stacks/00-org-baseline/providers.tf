###############################################################################
# File:        stacks/00-org-baseline/providers.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Provider configuration for the org-baseline stack. Uses a
#              single unaliased provider; the executing credentials
#              (Workload Identity Federation from CI, or
#              `gcloud auth application-default login` locally) must hold
#              roles/resourcemanager.organizationViewer at minimum, and
#              roles/essentialcontacts.admin at the Organization scope
#              when enable_essential_contacts = true.
###############################################################################

provider "google" {}

provider "google-beta" {}
