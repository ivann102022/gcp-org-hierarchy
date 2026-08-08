###############################################################################
# File:        stacks/30-org-policies/locals.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Derived values for the org-policies stack. Compiles the
#              curated catalog into a single map keyed by policy name and
#              resolves the dry_run flag per policy via enforce_overrides.
###############################################################################

locals {
  # From remote state.
  organization_id   = data.terraform_remote_state.org_baseline.outputs.organization_id
  organization_name = data.terraform_remote_state.org_baseline.outputs.organization_name

  # Effective dry_run per policy: enforce_overrides wins; else default_dry_run.
  # enforce_overrides[key] = true means "enforce" → dry_run = false.
  effective_dry_run = {
    for k in [
      "disable_sa_keys",
      "require_oslogin",
      "deny_external_ip",
      "prevent_public_storage",
      "restrict_sql_public_ip",
      "allowed_policy_member_domains",
      "trusted_image_projects",
      "resource_locations",
    ] : k => contains(keys(var.enforce_overrides), k) ? !var.enforce_overrides[k] : var.default_dry_run
  }

  # -----------------------------------------------------------------------------
  # Curated catalog compiled into a flat map. Each entry describes:
  #   constraint      — the GCP constraint ID (canonical, not org_prefix'd)
  #   spec            — the rules block spec (allow_all / deny_all / values)
  #   dry_run         — effective dry_run per var.enforce_overrides
  # -----------------------------------------------------------------------------
  catalog = {
    disable_sa_keys = var.enable_disable_sa_keys ? {
      constraint = "iam.disableServiceAccountKeyCreation"
      rules = [{
        enforce = true
      }]
      dry_run = local.effective_dry_run["disable_sa_keys"]
    } : null

    require_oslogin = var.enable_require_oslogin ? {
      constraint = "compute.requireOsLogin"
      rules = [{
        enforce = true
      }]
      dry_run = local.effective_dry_run["require_oslogin"]
    } : null

    deny_external_ip = var.enable_deny_external_ip ? {
      constraint = "compute.vmExternalIpAccess"
      rules = [{
        deny_all = true
      }]
      dry_run = local.effective_dry_run["deny_external_ip"]
    } : null

    prevent_public_storage = var.enable_prevent_public_storage ? {
      constraint = "storage.publicAccessPrevention"
      rules = [{
        enforce = true
      }]
      dry_run = local.effective_dry_run["prevent_public_storage"]
    } : null

    restrict_sql_public_ip = var.enable_restrict_sql_public_ip ? {
      constraint = "sql.restrictPublicIp"
      rules = [{
        enforce = true
      }]
      dry_run = local.effective_dry_run["restrict_sql_public_ip"]
    } : null

    allowed_policy_member_domains = var.enable_allowed_policy_member_domains ? {
      constraint = "iam.allowedPolicyMemberDomains"
      rules = [{
        values_allowed = var.allowed_customer_ids
      }]
      dry_run = local.effective_dry_run["allowed_policy_member_domains"]
    } : null

    trusted_image_projects = var.enable_trusted_image_projects ? {
      constraint = "compute.trustedImageProjects"
      rules = [{
        values_allowed = var.trusted_image_projects
      }]
      dry_run = local.effective_dry_run["trusted_image_projects"]
    } : null

    resource_locations = var.enable_resource_locations ? {
      constraint = "gcp.resourceLocations"
      rules = [{
        values_allowed = var.allowed_locations
      }]
      dry_run = local.effective_dry_run["resource_locations"]
    } : null
  }

  # Filter out null entries (disabled policies) and produce final map for for_each.
  enabled_catalog = {
    for k, v in local.catalog : k => v if v != null
  }
}
