###############################################################################
# File:        stacks/30-org-policies/outputs.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Public contract of the org-policies stack.
###############################################################################

output "org_policy_ids" {
  description = "Map of catalog key → org policy resource name. Empty when enable_org_policies = false."
  value = {
    for k, p in google_org_policy_policy.catalog : k => p.name
  }
}

output "org_policy_constraints" {
  description = "Map of catalog key → GCP constraint ID applied (e.g. 'iam.disableServiceAccountKeyCreation')."
  value = {
    for k, v in local.enabled_catalog : k => v.constraint
  }
}

output "org_policy_dry_run" {
  description = "Map of catalog key → whether the policy is in dry-run (audit only) or enforced. Consumers (dashboards, alerts) use this to filter which policies are actually blocking vs. observing."
  value = {
    for k, v in local.enabled_catalog : k => v.dry_run
  }
}

output "custom_org_policy_ids" {
  description = "Map of custom policy name → resource name."
  value = {
    for k, p in google_org_policy_policy.custom : k => p.name
  }
}
