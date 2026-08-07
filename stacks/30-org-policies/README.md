<!--
File:        stacks/30-org-policies/README.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Placeholder for the org-policies stack — planned for v0.2.0.
             Not yet scaffolded with HCL.
-->

# Stack `30-org-policies` (planned v0.2.0)

Curated set of `google_org_policy_policy` constraints at the Organization scope. Every constraint behind an `enable_<constraint>` switch; every constraint defaults to `dry_run = true` so the audit signal appears before enforcement.

**Not yet implemented.** Scaffolded as an empty directory to reserve the stack number and document intent. Implementation lands in v0.2.0.

## Planned catalogue

| Constraint | Default enforce state | Rationale |
|---|---|---|
| `iam.disableServiceAccountKeyCreation` | dry-run | Force Workforce Identity Federation; kill static SA-key rotation risk. |
| `compute.requireOsLogin` | dry-run | Auditable SSH via IAM. |
| `compute.vmExternalIpAccess` | dry-run | Deny all external IPs on VMs; force Cloud NAT / IAP. |
| `storage.publicAccessPrevention` | dry-run | Block accidentally-public buckets. |
| `sql.restrictPublicIp` | dry-run | Cloud SQL private-IP only. |
| `iam.allowedPolicyMemberDomains` | opt-in | Restrict IAM member domains (needs `allowed_customer_ids`). |
| `compute.trustedImageProjects` | opt-in | VM image allow-list. |
| `gcp.resourceLocations` | opt-in | Region pinning (default `in:eu-locations`). |

Plus `custom_org_policies` for arbitrary additions.

## Planned outputs

- `org_policy_ids` &mdash; constraint name &rarr; policy resource ID.
- `org_policy_dry_run` &mdash; constraint name &rarr; whether dry-run is on.

## Cross-references

- [../../docs/architecture.md](../../docs/architecture.md) &mdash; section "`30-org-policies` (planned v0.2.0)".
- [../../docs/contract.md](../../docs/contract.md) &mdash; planned outputs.
