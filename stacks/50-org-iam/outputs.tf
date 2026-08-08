###############################################################################
# File:        stacks/50-org-iam/outputs.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Public contract of the org-iam stack.
###############################################################################

output "org_iam_bindings" {
  description = "Map of role → list of members bound at Org scope. Consolidates the curated bindings for downstream audit / verification consumers."
  value = {
    for role, members in local.curated_role_members :
    role => members if length(members) > 0
  }
}

output "custom_org_iam_bindings" {
  description = "Map of binding_key → { role, members } echo of the custom bindings."
  value       = var.custom_org_iam_bindings
}

output "break_glass_configured" {
  description = "True when break_glass_principals is non-empty. Consumed by gcp-observability-baseline's alert policy (log-based alert on break-glass principal usage)."
  value       = local.break_glass_configured
}

output "break_glass_principals" {
  description = "Echo of the break-glass principals list — consumed by observability-baseline alert filter (so the log-based alert can filter for 'protoPayload.authenticationInfo.principalEmail' matching one of these)."
  value       = var.break_glass_principals
}
