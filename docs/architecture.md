<!--
File:        docs/architecture.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Architecture reference for gcp-org-hierarchy — the layered
             repo model in GCP, why hierarchy is Tier 0, why platform
             projects live here (not in the LZ), and per-stack design
             rationale. Non-obvious decisions are extracted to ADRs
             under docs/adr/.
-->

# Architecture

## Layered repo model (GCP)

```
Tier 3  Extensions / workloads         (future — systems-projects/*)
Tier 2  Landing zone(s)                (landing-zones/gcp-lz-*)
Tier 1  Platform baselines             (baseline-projects/gcp-*-baseline)
Tier 0  ORGANIZATION HIERARCHY         ← THIS REPO
Tier -1 Shared modules                 (shared-modules/terraform-gcp-modules)
```

Each tier knows only the one below via a documented contract. In GCP, Tier 0 exists because Google leaves the folder tree, the project factory, and the org policies to you — they arrive empty with your Cloud Identity tenant. This is different from AWS (where Tier 0 also creates the Organization itself) and closer to Azure (where the tenant arrives but Management Groups must be designed and provisioned).

Cross-CSP contrast summarised:

| CSP | How the "top of the tree" arrives |
|---|---|
| **AWS** | You create it. `aws_organizations_organization`, OUs, accounts. No shortcut. |
| **GCP** | Comes with Google Workspace / Cloud Identity. **Folders are optional structure inside it, but every enterprise wants them.** |
| **Azure** | Comes with the Entra ID tenant. Management Groups are optional structure inside it. |

## Why platform projects live here, not in each LZ

Superficially, the platform projects (`plogs`, `pmgm`, `piam`, `pdns`, `pingress`, `sandbox`) could be created by whichever LZ deploys first — the GCP LZs even ship a `create_projects = true` mode for that. In practice, that pattern collapses when a second LZ appears: the two LZs either fight for ownership of the same project IDs or drift into inconsistent naming.

Making Tier 0 the sole owner:

- Every LZ consumes the same `platform_project_ids` map. Zero drift.
- Every baseline knows where to deploy (`plogs` for observability, `pmgm` for KMS, `pdns` for Cloud DNS, ...).
- Projects can move between folders (`google_project.folder_id`) without needing to reprovision.
- The LZ's `create_projects = true` mode remains as a fallback for greenfield / demo deployments where a full Tier 0 is not being run.

Full rationale in [ADR-0002](adr/0002-platform-projects-here-not-in-lz.md).

## Why the org log sink lives here, not in observability-baseline

`google_logging_organization_sink` is an **org-scope resource** — creating it requires `roles/logging.configWriter` at the Organization level. Observability-baseline is written to run inside a single project (`plogs`) with project-scope permissions. Putting the org sink in observability-baseline would force the baseline to hold org-level rights it does not otherwise need.

Split:

- **Tier 0 (this repo, stack `40-org-logging`)** creates the org sink and points it at `plogs`. Creates the writer-identity IAM binding on `plogs`.
- **Tier 1 (`gcp-observability-baseline`)** operates *inside* `plogs`: log buckets, retention policies, exclusions, exports to BigQuery, dashboards, alerts.

Full rationale in [ADR-0003](adr/0003-org-sink-in-tier0-not-obs-baseline.md).

## Why Workforce Identity Federation is not here

WIF is often lumped into "org hierarchy" material because it's org-scope in name. It is not:

- WIF pools / providers can be created at the project scope (`google_iam_workforce_pool` targets a workforce federation project — typically `piam`).
- WIF is intimately coupled to group-based IAM patterns, custom roles, break-glass procedures — all of which are **identity discipline** (Tier 1), not hierarchy discipline (Tier 0).
- Coupling WIF to Tier 0 would force every hierarchy change to redeploy identity infrastructure. Wrong blast-radius alignment.

Split: this repo creates `piam` (the project). `gcp-identity-baseline` provisions WIF pools, groups, custom roles, and break-glass patterns inside `piam`. Full rationale in [ADR-0004](adr/0004-no-workforce-identity-federation-here.md).

## The two organization modes

Every stack in this repo honours `organization_mode` with two values:

| Mode | Behaviour | Use case |
|---|---|---|
| `existing` (default) | Every resource is a data source. Terraform reads pre-existing folders / projects and re-exports them via the contract. Zero side effects. | Any pre-existing customer Org — bring-your-own. |
| `create` | Vanilla Terraform provisions folders + platform projects + org-policies + org-sink. Full IaC control. | Greenfield deployment. |

There is no `blueprint` or `control_tower` mode in v0.1.0. Google Cloud Foundation Fabric is Terraform code you consume, not a runtime peer of Terraform in the way AWS Control Tower is. If Fabric integration becomes a hard requirement, it lands as a future `blueprint` mode. Full rationale in [ADR-0001](adr/0001-two-modes-only-existing-and-create.md).

The two modes produce the **same output shape** (see [contract.md](contract.md)) so downstream consumers stay agnostic.

## Stack-by-stack

### `00-org-baseline`

- **Owns**: `data "google_organization"` (always a data source — GCP does not let you create Organizations from Terraform), and optionally `google_essential_contacts_contact` at the Organization scope for security / billing / technical notifications.
- **Inputs of note**: `organization_domain` (used to look up the Org), `billing_account_id` (passed through to `20-projects`), `essential_contacts` (map of category → email list).
- **Outputs**: `organization_id`, `organization_domain`, `billing_account_id`, `mode`.

### `10-folders`

- **Owns**: the folder tree. Accepts a nested map of folder names → children (arbitrary depth up to GCP's 10-level limit).
- **Reference tree** (default, aligned with Cloud Foundation Fabric):
  - `Platform` — holds the platform projects created in stack `20`.
  - `LandingZones` — parent of every Tier 2 LZ's projects. Sub-folders per environment optional (`Production`, `NonProduction`).
  - `Sandbox` — ephemeral / experimental projects.
- **Modes**: `create` provisions; `existing` reads pre-existing folders by display-name lookup.

### `20-projects`

- **Owns**: the platform projects, provisioned via the shared `projects` module (`git::…/terraform-gcp-modules.git//modules/projects?ref=v0.1.0`).
- **Reference project set** (default, one per platform concern):
  - `plogs` — org sink destination + centralized logs, hosted in the `Platform` folder.
  - `pmgm` — KMS central + management, hosted in `Platform`.
  - `piam` — identity foundation (WIF pools land here in `gcp-identity-baseline`).
  - `pdns` — Cloud DNS host (zones land here in `gcp-dns-baseline`).
  - `pingress` — shared ingress baseline.
  - `sandbox` — sandbox, hosted in the `Sandbox` folder.
- **`deletion_policy = "PREVENT"`** on every platform project (provider &gt;=6 default). Rationale: deleting a platform project cascades into every service and every audit log — accidental `terraform destroy` must fail loud. To genuinely destroy, override the policy per project, apply, then destroy.
- **Modes**: `create` provisions; `existing` reads by project ID.

### `30-org-policies` (planned v0.2.0)

- **Owns**: `google_org_policy_policy` at Org scope, curated catalogue with per-policy `enable_X` switches.
- **All policies default to `dry_run = true`** — surfaces violations in the audit log without blocking. Consumers flip to enforce individually after review.
- **Catalogue** (initial 8):
  - `iam.disableServiceAccountKeyCreation` — force WIF.
  - `compute.requireOsLogin` — auditable SSH via IAM.
  - `compute.vmExternalIpAccess` — deny all external IPs on VMs; force NAT / IAP.
  - `storage.publicAccessPrevention` — block public buckets.
  - `sql.restrictPublicIp` — Cloud SQL private-IP only.
  - `iam.allowedPolicyMemberDomains` — restrict IAM member domains (opt-in; requires `allowed_customer_ids`).
  - `compute.trustedImageProjects` — VM image allow-list (opt-in).
  - `gcp.resourceLocations` — region pinning (opt-in; defaults to `in:eu-locations`).
- **Custom policies**: `custom_org_policies` map for arbitrary additions.

### `40-org-logging` (planned v0.2.0)

- **Owns**: `google_logging_organization_sink` at Org scope, IAM binding on `plogs` for the sink's writer identity.
- **Filter default**: `""` (all logs). Consumers can override with a curated filter for cost control.
- **Downstream**: `gcp-observability-baseline` consumes `log_sink_writer_identity` + `log_sink_destination` and configures buckets / retention / exports inside `plogs`.

### `50-org-iam` (planned v0.3.0)

- **Owns**: `google_organization_iam_member` for a curated set of org-scope roles (Org Admin, Project Creator, Billing Admin, Security Admin, break-glass user).
- **Excludes** Workforce Identity Federation (see [ADR-0004](adr/0004-no-workforce-identity-federation-here.md)) and identity-baseline's custom roles.

### `60-tags` (planned v0.3.0)

- **Opt-in** (`create_tags = false` default).
- **Owns**: `google_tags_tag_key` + `google_tags_tag_value` at Org scope for cross-tier governance (e.g. `environment=prod|nonprod`, `data-classification=public|internal|confidential`). Also demonstrates one tag-based IAM condition as reference.

## Apply order

Within this repo:

```
00-org-baseline → 10-folders → 20-projects → (30 → 40 → 50 → 60 once shipped)
```

Downstream (Tier 1 baselines + Tier 2 LZs) consumes Tier 0 via `terraform_remote_state`. Both wait for Tier 0 to be applied at least through `20-projects` (that's where `platform_project_ids` becomes available).

## What this repo does NOT do

- **Does not create the Organization itself** — it's a Google Workspace / Cloud Identity artefact.
- **Does not deploy VPCs, NAT, firewalls, or FortiGates** — that's Tier 2.
- **Does not deploy DNS zones, log dashboards, KMS keys, or SCC config** — that's Tier 1 (inside the platform projects this repo creates).
- **Does not configure Workforce Identity Federation** — that's Tier 1 identity-baseline. See [ADR-0004](adr/0004-no-workforce-identity-federation-here.md).
- **Does not manage the state bucket** — bootstrap is a one-time shell script.

## Failure modes and blast radius

- **`create` mode against pre-existing folders with the same display name** — `google_folder` errors on unique constraint at parent scope. Recovery: switch to `existing` mode, or delete the pre-existing folder (unlikely acceptable).
- **First apply of stack `40-org-logging` (v0.2.0)** — org-sink writer identity propagation lag can cause the follow-on `google_project_iam_member` binding to fail with "principal not found". Recovery: re-apply after 30 seconds; Terraform retries the binding cleanly.
- **`terraform destroy` on stack `20-projects`** — fails by design because every platform project inherits `deletion_policy = "PREVENT"`. To genuinely destroy, override the policy per project, apply, then destroy. Two-step protection is intentional.
- **Org-policy enforcement (v0.2.0) breaking a live workload** — mitigated by `dry_run = true` default in the catalogue. A policy flipped to enforce that breaks workloads is a rollback: revert the specific `enable_X` switch, apply.
