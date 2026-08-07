###############################################################################
# File:        stacks/00-org-baseline/outputs.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Public contract of the org-baseline stack. Every downstream
#              stack and every downstream repo reads these outputs via
#              terraform_remote_state. Contract spec in docs/contract.md.
###############################################################################

output "organization_id" {
  description = "Numeric ID of the GCP Organization (e.g. '123456789012'). Stable across both modes."
  value       = local.organization_id
}

output "organization_domain" {
  description = "Primary domain of the GCP Organization (e.g. 'example.com')."
  value       = local.organization_domain
}

output "organization_name" {
  description = "Fully-qualified name of the Organization ('organizations/<org_id>'). Convenience for APIs that expect the qualified form."
  value       = local.organization_name
}

output "billing_account_id" {
  description = "Billing account ID that platform projects (stack 20-projects) attach to. Exposed for downstream consumers that need to link additional projects to the same billing account."
  value       = var.billing_account_id
}

output "mode" {
  description = "Echoes the organization_mode variable. Consumers can use this in precondition blocks."
  value       = var.organization_mode
}

output "essential_contact_emails" {
  description = "List of essential contact emails provisioned by this stack. Empty when enable_essential_contacts = false."
  value       = [for c in google_essential_contacts_contact.org : c.email]
}
