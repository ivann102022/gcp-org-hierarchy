###############################################################################
# File:        stacks/00-org-baseline/locals.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Derived values for the org-baseline stack. Extracts the
#              organization_id from the data-source lookup so downstream
#              blocks and outputs reference a single canonical value.
###############################################################################

locals {
  # data.google_organization.this exposes both .org_id (numeric) and .name
  # ('organizations/123456789012'). Downstream stacks and consumers use both
  # forms depending on the resource API — expose the numeric form as the
  # primary output; construct the 'organizations/…' form on demand.
  organization_id     = data.google_organization.this.org_id
  organization_name   = data.google_organization.this.name
  organization_domain = data.google_organization.this.domain
}
