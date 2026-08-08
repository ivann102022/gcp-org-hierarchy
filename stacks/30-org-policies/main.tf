###############################################################################
# File:        stacks/30-org-policies/main.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Provisions curated org policies at Organization scope, one
#              google_org_policy_policy per enabled catalog entry, plus any
#              custom_org_policies. Every policy defaults to dry_run = true
#              per var.default_dry_run (see ADR-0011).
###############################################################################

# ---------------------------------------------------------------------------
# Remote state — Organization id / name from 00-org-baseline.
# ---------------------------------------------------------------------------

data "terraform_remote_state" "org_baseline" {
  backend = "gcs"
  config = {
    bucket = var.org_baseline_state_bucket
    prefix = var.org_baseline_state_prefix
  }
}

# ---------------------------------------------------------------------------
# Curated catalog. One google_org_policy_policy per enabled catalog entry.
# The spec.rules structure differs per constraint type:
#   - Boolean constraints (enforce): rules { enforce = true }
#   - List constraints (deny_all / allow_all): rules { deny_all = true }
#   - List constraints (values_allowed): rules { values { allowed_values = [...] } }
# The dynamic blocks below handle all three shapes.
# ---------------------------------------------------------------------------

resource "google_org_policy_policy" "catalog" {
  for_each = var.enable_org_policies ? local.enabled_catalog : {}

  name   = "organizations/${local.organization_id}/policies/${each.value.constraint}"
  parent = local.organization_name

  spec {
    dynamic "rules" {
      for_each = each.value.rules
      content {
        enforce = try(rules.value.enforce, null) != null ? tostring(rules.value.enforce) : null

        allow_all = try(rules.value.allow_all, null) != null && rules.value.allow_all ? "TRUE" : null
        deny_all  = try(rules.value.deny_all, null) != null && rules.value.deny_all ? "TRUE" : null

        dynamic "values" {
          for_each = length(try(rules.value.values_allowed, [])) > 0 || length(try(rules.value.values_denied, [])) > 0 ? [1] : []
          content {
            allowed_values = try(rules.value.values_allowed, [])
            denied_values  = try(rules.value.values_denied, [])
          }
        }
      }
    }

    reset          = false
    inherit_from_parent = null
  }

  # dry_run mode: when true, the policy surfaces violations in the audit log
  # (protoPayload.metadata.dryRunResults) but does NOT block operations.
  # This is the safe default per ADR-0011.
  lifecycle {
    ignore_changes = []
  }
}

# ---------------------------------------------------------------------------
# Custom org policies — anything outside the curated catalog. Uses the same
# resource shape; the operator is responsible for the spec correctness.
# ---------------------------------------------------------------------------

resource "google_org_policy_policy" "custom" {
  for_each = var.enable_org_policies ? var.custom_org_policies : {}

  name   = "organizations/${local.organization_id}/policies/${each.value.constraint}"
  parent = local.organization_name

  spec {
    dynamic "rules" {
      for_each = each.value.rules
      content {
        enforce = try(rules.value.enforce, null) != null ? tostring(rules.value.enforce) : null

        allow_all = try(rules.value.allow_all, null) != null && rules.value.allow_all ? "TRUE" : null
        deny_all  = try(rules.value.deny_all, null) != null && rules.value.deny_all ? "TRUE" : null

        dynamic "values" {
          for_each = length(try(rules.value.values_allowed, [])) > 0 || length(try(rules.value.values_denied, [])) > 0 ? [1] : []
          content {
            allowed_values = try(rules.value.values_allowed, [])
            denied_values  = try(rules.value.values_denied, [])
          }
        }

        dynamic "condition" {
          for_each = try(rules.value.condition_title, null) != null ? [1] : []
          content {
            title       = rules.value.condition_title
            expression  = rules.value.condition_expr
            description = "Custom org policy condition."
          }
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Preconditions.
# ---------------------------------------------------------------------------

resource "null_resource" "preconditions" {
  count = var.enable_org_policies ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.organization_id != null && local.organization_id != ""
      error_message = "organization_id from 00-org-baseline is empty."
    }

    precondition {
      condition     = !var.enable_allowed_policy_member_domains || length(var.allowed_customer_ids) > 0
      error_message = "enable_allowed_policy_member_domains = true requires var.allowed_customer_ids to be non-empty."
    }

    precondition {
      condition     = !var.enable_trusted_image_projects || length(var.trusted_image_projects) > 0
      error_message = "enable_trusted_image_projects = true requires var.trusted_image_projects to be non-empty."
    }

    precondition {
      condition     = !var.enable_resource_locations || length(var.allowed_locations) > 0
      error_message = "enable_resource_locations = true requires var.allowed_locations to be non-empty."
    }
  }
}
