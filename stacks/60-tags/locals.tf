###############################################################################
# File:        stacks/60-tags/locals.tf
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: Derived values for the tags stack. Compiles the reference
#              catalog into a map of tag keys and a flattened map of
#              tag values.
###############################################################################

locals {
  # From remote state.
  organization_id   = data.terraform_remote_state.org_baseline.outputs.organization_id
  organization_name = data.terraform_remote_state.org_baseline.outputs.organization_name

  # -----------------------------------------------------------------------------
  # Reference tag key catalog. Each entry generates one google_tags_tag_key.
  # -----------------------------------------------------------------------------
  reference_tag_keys = var.create_reference_tag_set ? merge(
    {
      environment = {
        description = "Deployment environment. Governs org-policy strength, retention, backup frequency, on-call routing."
        values      = var.reference_environment_values
      }
      "data-classification" = {
        description = "Data sensitivity level. Governs encryption, retention, access control, cross-region replication."
        values      = var.reference_data_classification_values
      }
    },
    var.enable_cost_center_tag ? {
      "cost-center" = {
        description = "Cost center for billing rollup. Free-form values (populated per customer's finance taxonomy)."
        values      = []
      }
    } : {},
    var.enable_owner_tag ? {
      owner = {
        description = "Owning team / business unit. Free-form values."
        values      = []
      }
    } : {},
  ) : {}

  # -----------------------------------------------------------------------------
  # Full tag key map: reference + custom.
  # -----------------------------------------------------------------------------
  all_tag_keys = merge(local.reference_tag_keys, var.custom_tag_keys)

  # -----------------------------------------------------------------------------
  # Flatten tag values into a map keyed by 'key_name/value_name' — stable
  # composite key for for_each on google_tags_tag_value.
  # -----------------------------------------------------------------------------
  all_tag_values = merge([
    for key_name, key_spec in local.all_tag_keys : {
      for value in key_spec.values :
      "${key_name}/${value}" => {
        key_name = key_name
        value    = value
      }
    }
  ]...)
}
