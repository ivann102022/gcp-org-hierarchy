<!--
File:        stacks/30-org-policies/README.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Documentation for the org-policies stack — curated catalog
             of google_org_policy_policy at Organization scope with
             dry-run defaults.
-->

# Stack `30-org-policies`

Curated catalog of `google_org_policy_policy` resources at Organization scope. Every catalog policy is opt-in via its own `enable_*` switch and defaults to **dry-run** so violations surface in the audit log without blocking operations.

The curated catalog and the dry-run-by-default design are documented in [ADR-0011](../../docs/adr/0011-curated-org-policy-catalog.md).

## What it owns

- `google_org_policy_policy.catalog` &mdash; one resource per enabled catalog entry (8 policies in v0.1.0 of the stack).
- `google_org_policy_policy.custom` &mdash; one resource per entry in `var.custom_org_policies`.

Both types attach at the Organization scope (`parent = organizations/<id>`). Policies inherit down the folder tree by default; downstream folders / projects can override or exempt via their own policy resources.

## Curated catalog

| Catalog key | GCP constraint | Purpose |
|---|---|---|
| `disable_sa_keys` | `iam.disableServiceAccountKeyCreation` | Kills user-managed SA keys; forces WIF / short-lived credentials |
| `require_oslogin` | `compute.requireOsLogin` | SSH via IAM (auditable) instead of project-wide SSH keys |
| `deny_external_ip` | `compute.vmExternalIpAccess` (deny all) | No public IPs on VMs; forces Cloud NAT + IAP tunnels |
| `prevent_public_storage` | `storage.publicAccessPrevention` | Blocks the "public bucket" data exposure vector |
| `restrict_sql_public_ip` | `sql.restrictPublicIp` | Cloud SQL private-IP only |
| `allowed_policy_member_domains` | `iam.allowedPolicyMemberDomains` | Restrict IAM member domains to Workspace customer ID allow-list |
| `trusted_image_projects` | `compute.trustedImageProjects` | VM boot disk image allow-list |
| `resource_locations` | `gcp.resourceLocations` | Region pinning (e.g. `in:eu-locations`) |

Each policy is enabled individually (`enable_disable_sa_keys = true`, etc.) and stays in dry-run until you flip it to enforce via `enforce_overrides = { disable_sa_keys = true }`.

## The dry-run-first workflow

Recommended activation order in a live deployment (from safest to most operationally sensitive):

1. `prevent_public_storage` &mdash; enable + enforce day 1. Near-zero false positive rate.
2. `disable_sa_keys` &mdash; enable + enforce. WIF-first pipelines tolerate this immediately.
3. `restrict_sql_public_ip` &mdash; enable + enforce. Private SQL is baseline.
4. `require_oslogin` &mdash; enable in dry-run first; enforce after SSH via IAM is validated with real users.
5. `deny_external_ip` &mdash; enable in dry-run; enforce after Cloud NAT is verified across all VMs.
6. `resource_locations` &mdash; enable in dry-run; enforce after audit shows workloads honour the target region set.
7. `allowed_policy_member_domains` &mdash; enable + enforce once `allowed_customer_ids` is populated correctly.
8. `trusted_image_projects` &mdash; enable in dry-run first; enforce after golden images are catalogued and validated.

Full rationale for the dry-run-first workflow in [ADR-0011](../../docs/adr/0011-curated-org-policy-catalog.md).

## What it does NOT do

- Does not attach policies at folder or project scope &mdash; that belongs to `10-folders` extensions (hierarchical firewall policies pattern), Tier 1 baselines, or Tier 2 LZs. This stack is Org-scope only.
- Does not create custom constraints (`google_org_policy_custom_constraint`) &mdash; catalog uses Google-managed constraints only. Add via `custom_org_policies` if you have a custom-constraint use case.
- Does not manage exceptions per project or folder &mdash; exception patterns via IAM Conditions + folder-scoped policy overrides belong at the folder level, not here.

## Inputs

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `org_baseline_state_bucket` | Yes | &mdash; | Remote-state bucket for `00-org-baseline`. |
| `enable_org_policies` | No | `false` | Master switch. |
| `default_dry_run` | No | `true` | Global default for the dry_run flag. |
| `enforce_overrides` | No | `{}` | Per-policy override to promote from dry-run to enforce. |
| `enable_disable_sa_keys`, `enable_require_oslogin`, ..., `enable_resource_locations` | No | `false` each | Per-catalog-policy enable. |
| `allowed_customer_ids` | Required if `enable_allowed_policy_member_domains` | `[]` | Workspace customer IDs allow-list. |
| `trusted_image_projects` | Required if `enable_trusted_image_projects` | `[]` | VM image source project allow-list. |
| `allowed_locations` | No | `["in:eu-locations"]` | Region pinning allow-list. |
| `custom_org_policies` | No | `{}` | Custom constraint entries outside the catalog. |

Full spec in [`variables.tf`](variables.tf).

## Outputs

| Output | Type | Purpose |
|---|---|---|
| `org_policy_ids` | `map(string)` | Catalog key &rarr; resource name. |
| `org_policy_constraints` | `map(string)` | Catalog key &rarr; GCP constraint ID. |
| `org_policy_dry_run` | `map(bool)` | Catalog key &rarr; whether currently in dry-run. Consumed by dashboards / alert policies. |
| `custom_org_policy_ids` | `map(string)` | Custom policy name &rarr; resource name. |

Full contract in [`../../docs/contract.md`](../../docs/contract.md).

## Required IAM

- `roles/orgpolicy.policyAdmin` at the Organization scope.

## Apply

```bash
terraform -chdir=stacks/30-org-policies init
terraform -chdir=stacks/30-org-policies plan
terraform -chdir=stacks/30-org-policies apply
```

## Failure modes

- **`enable_org_policies = true` with no policy enabled**: valid; the stack is a no-op. Terraform state is clean.
- **Policy flipped to enforce blocks a live workload**: rollback is fast &mdash; remove that key from `enforce_overrides` (returns it to dry-run) and re-apply. The policy stays in place, just in observe mode again.
- **`allowed_policy_member_domains` with wrong customer IDs**: locks out IAM bindings from your Workspace tenant. Recovery: unset the constraint or add the correct customer ID via the console with an Org Admin identity.
- **`terraform destroy`**: removes all policies, returning behaviour to GCP defaults. Coordinate with security team before destroying &mdash; this is a real security-posture change.
