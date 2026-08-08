<!--
File:        stacks/60-tags/README.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Documentation for the tags stack — Resource Manager tag keys
             and values at Organization scope, opt-in by default.
-->

# Stack `60-tags`

Provisions **Resource Manager tag keys and tag values** at Organization scope for cross-tier governance: tag-based IAM Conditions, tag-based org policy exceptions, tag-based hierarchical firewall rules, and cost attribution via Cloud Billing's native integration with Resource Manager Tags (no intermediate label conversion required for the Tag &rarr; cost linkage).

Opt-in (`enable_tags = false` by default) because tagging introduces ongoing operational cost &mdash; the value is only realised if downstream consumers actually bind tags to resources with discipline. Design rationale in [ADR-0014](../../docs/adr/0014-tag-catalog-choice.md).

## What it owns

- `google_tags_tag_key` &mdash; one per entry in the merged catalog (reference + custom).
- `google_tags_tag_value` &mdash; one per (key, value) pair. Parented to the tag key so Terraform's dependency graph orders creation correctly.

Every key ships with `purpose = "GCE_FIREWALL"` so the tag can be used in hierarchical firewall policies. **⚠ Under review** &mdash; the claim that this purpose is "maximally-capable with no downside" for governance-only tags (cost-center, owner, data-classification) is being verified against current GCP semantics. See [`docs/pending-corrections.md`](../../docs/pending-corrections.md). No code change yet; documentation-level flag while research is done.

## Reference catalog (default)

| Tag key | Purpose | Reference values |
|---|---|---|
| `environment` | Deployment environment. Governs org-policy strength, retention, backup frequency, on-call routing. | `prod`, `preprod`, `dev` |
| `data-classification` | Data sensitivity. Governs encryption, retention, access, cross-region replication. | `public`, `internal`, `confidential`, `restricted` |
| `cost-center` | Cost attribution rollup. Free-form values (populate per customer's finance taxonomy). | &mdash; |
| `owner` | Owning team / BU. Free-form values. | &mdash; |

Values match the portfolio's folder tree conventions (env values map to `PRO/PRE/DEV` folder names, lowercased per GCP tag naming rules).

## What it does NOT do

- Does not bind tags to resources &mdash; that's the responsibility of whichever stack owns the resource. This stack only provisions the taxonomy.
- Does not create IAM Conditions or org-policy conditions that reference tags &mdash; example patterns are documented but not enforced here.
- Does not create billing labels &mdash; Labels are a separate GCP mechanism (per-resource key/value metadata usable for billing filtering and inventory queries), independent from Resource Manager Tags. This stack ships Tags; Labels can be added separately at the resource-owning stacks where they apply. **Note**: Cost attribution via Tags does NOT require converting Tags to Labels &mdash; Cloud Billing integrates directly with Resource Manager Tags for cost allocation and chargeback. Downstream reporting may still use billing export + BigQuery for advanced analytics, but the Tag &rarr; cost linkage itself is native.

## Inputs

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `org_baseline_state_bucket` | Yes | &mdash; | Remote state for `00-org-baseline`. |
| `enable_tags` | No | `false` | Master switch (opt-in). |
| `create_reference_tag_set` | No | `true` | Provision the reference catalog when the stack is enabled. |
| `reference_environment_values` | No | `["prod", "preprod", "dev"]` | Values for `environment` key. |
| `reference_data_classification_values` | No | `["public", "internal", "confidential", "restricted"]` | Values for `data-classification` key. |
| `enable_cost_center_tag` | No | `true` | Whether to provision the `cost-center` key. |
| `enable_owner_tag` | No | `true` | Whether to provision the `owner` key. |
| `custom_tag_keys` | No | `{}` | Additional tag keys outside the reference set. |

Full spec in [`variables.tf`](variables.tf).

## Outputs

| Output | Type | Purpose |
|---|---|---|
| `tag_keys` | `map(string)` | Key name &rarr; `"tagKeys/<numeric_id>"`. |
| `tag_key_ids_numeric` | `map(string)` | Key name &rarr; numeric ID only. Convenience. |
| `tag_values` | `map(string)` | `"key/value"` &rarr; `"tagValues/<numeric_id>"`. |
| `tag_catalog` | `map(list(string))` | Key name &rarr; list of allowed values. Human-readable summary. |

Full contract in [`../../docs/contract.md`](../../docs/contract.md).

## Required IAM

- `roles/resourcemanager.tagAdmin` at the Organization scope.

## Apply

```bash
terraform -chdir=stacks/60-tags init
terraform -chdir=stacks/60-tags plan
terraform -chdir=stacks/60-tags apply
```

## Downstream usage example

Bind a tag value to a project (typically from that project's own Terraform stack, not from this one):

```hcl
data "terraform_remote_state" "tags" {
  backend = "gcs"
  config = {
    bucket = var.org_state_bucket
    prefix = "gcp-org-hierarchy/60-tags"
  }
}

resource "google_tags_tag_binding" "project_env_prod" {
  parent    = "//cloudresourcemanager.googleapis.com/projects/${google_project.workload.number}"
  tag_value = data.terraform_remote_state.tags.outputs.tag_values["environment/prod"]
}
```

Use the tag in an IAM Condition on a role binding:

```hcl
resource "google_project_iam_member" "prod_admin_via_tag" {
  project = google_project.workload.project_id
  role    = "roles/editor"
  member  = "group:prod-admins@example.com"
  condition {
    title       = "Only in prod"
    description = "Role active only when project has environment=prod tag"
    expression  = "resource.matchTag(\"${var.org_id}/environment\", \"prod\")"
  }
}
```

## Failure modes

- **Removing a tag value from `reference_*_values` while resources still reference it**: `google_tags_tag_value` destroy fails because bindings exist. Recovery: remove the bindings first (in the resource-owning stacks), then re-apply this stack.
- **Naming collisions with existing tag keys**: `google_tags_tag_key` requires uniqueness per parent scope (Org). Common when someone created a tag via console before this stack existed. Recovery: either delete the console-created tag (loses history) or rename via `custom_tag_keys` to avoid collision.
- **Value validation failure**: tag value short_names must be lowercase alphanumeric with `-` or `_`. Precondition catches this at plan time.
- **`terraform destroy`**: removes all tag keys / values. Any resource binding is orphaned and IAM Conditions / org policies referencing the tags fail. Coordinate destroy with a full inventory of tag consumers.
