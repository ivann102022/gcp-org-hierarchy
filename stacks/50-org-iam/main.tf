###############################################################################
# File:        stacks/50-org-iam/main.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Provisions org-scope IAM bindings for the curated privileged
#              role set. Uses google_organization_iam_member (per-member)
#              rather than google_organization_iam_binding (authoritative
#              per role) to avoid stomping on bindings created outside
#              Terraform for the same role. See ADR-0013.
###############################################################################

# ---------------------------------------------------------------------------
# Remote state — Organization id from 00-org-baseline.
# ---------------------------------------------------------------------------

data "terraform_remote_state" "org_baseline" {
  backend = "gcs"
  config = {
    bucket = var.org_baseline_state_bucket
    prefix = var.org_baseline_state_prefix
  }
}

# ---------------------------------------------------------------------------
# Curated role bindings. Per-member (not authoritative) so this stack does
# not stomp on other legitimate bindings for the same role (e.g. a
# Workspace-managed super-admin).
# ---------------------------------------------------------------------------

resource "google_organization_iam_member" "curated" {
  for_each = var.enable_org_iam ? local.curated_bindings : {}

  org_id = local.organization_id
  role   = each.value.role
  member = each.value.member
}

# ---------------------------------------------------------------------------
# Custom bindings.
# ---------------------------------------------------------------------------

resource "google_organization_iam_member" "custom" {
  for_each = var.enable_org_iam ? local.custom_bindings : {}

  org_id = local.organization_id
  role   = each.value.role
  member = each.value.member
}

# ---------------------------------------------------------------------------
# Preconditions.
# ---------------------------------------------------------------------------

resource "null_resource" "preconditions" {
  count = var.enable_org_iam ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.organization_id != null && local.organization_id != ""
      error_message = "organization_id from 00-org-baseline is empty."
    }

    # Warn (via error) if no org_admins configured — leaving the Org without
    # any Terraform-managed admin is almost certainly a misconfiguration.
    precondition {
      condition     = length(var.org_admins) > 0 || length(var.break_glass_principals) > 0
      error_message = "enable_org_iam = true with no org_admins and no break_glass_principals leaves the Org without any Terraform-managed Organization Admin binding. Configure at least one, even if only for break-glass."
    }

    # Every member must be in canonical GCP format.
    precondition {
      condition = alltrue([
        for k, v in local.curated_bindings :
        can(regex("^(user|group|serviceAccount|domain):", v.member))
      ])
      error_message = "Every principal must start with 'user:', 'group:', 'serviceAccount:', or 'domain:'."
    }
  }
}
