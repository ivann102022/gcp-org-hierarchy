<!--
File:        README.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Entry point for gcp-org-hierarchy — Tier 0 of the GCP
             stacked-repo taxonomy. Owns the folder hierarchy, the
             platform project factory, org policies, org-level logging
             sink, and organization IAM. Every GCP baseline
             (baseline-projects/gcp-*-baseline) and landing zone
             (landing-zones/gcp-lz-*) consumes this via
             terraform_remote_state.
-->

# GCP Organization Hierarchy

**Tier 0** of the GCP stacked-repo taxonomy. Owns everything **structural** about the GCP Organization: the folder hierarchy, the platform project factory (`plogs`, `pmgm`, `piam`, `pdns`, `pingress`, `sandbox`), organization policies, the organization-level log sink, org-scoped IAM bindings, essential contacts, and (optionally) resource-manager tag keys/values at the organisation scope.

Every GCP Landing Zone (`landing-zones/gcp-lz-*`) and every GCP baseline (`baseline-projects/gcp-*-baseline`) consumes the outputs of this repo via `terraform_remote_state`. Swap the LZ, swap the baseline; keep the hierarchy.

## Why a separate repo

**In GCP the Organization itself is not created by Terraform** — it arrives with your Cloud Identity / Google Workspace tenant. So this repo does **not** own the Organization resource. What it does own is everything Google leaves to you:

- The **folder tree** that groups platform / landing zones / sandbox concerns.
- The **project factory** that provisions the platform projects into which every baseline deploys.
- The **org policies** (`google_org_policy_policy`) that constrain every project under the Org.
- The **organization-level log sink** (only Org Admin can create; Layer 0 concern).
- **Organization-scope IAM** bindings and essential contacts.
- Optionally, **Resource Manager tag keys/values** at the Org scope for cross-tier governance.

These live together because they share one lifecycle: **change rarely, blast radius huge**. Splitting them off from the LZ (where they were previously mixed in stack `00-network-core`) mirrors what `aws-org-hierarchy/` does for AWS and what `azure-mg-hierarchy/` will do for Azure.

## What this repo does NOT do

- **Does not create the Organization itself** — the Organization is a Google Workspace / Cloud Identity artefact. Terraform only references it via `data "google_organization"`.
- **Does not deploy VPCs, NAT, firewalls, or FortiGates** — that's the landing zone (Tier 2).
- **Does not enable SCC, Cloud Logging dashboards, DNS zones, or KMS keys inside `plogs` / `pmgm` / `pdns`** — that's the corresponding Tier 1 baseline. This repo only creates the projects (containers); the baselines fill them.
- **Does not configure Workforce Identity Federation** — that lives in `gcp-identity-baseline` (Tier 1). Rationale in [ADR-0004](docs/adr/0004-no-workforce-identity-federation-here.md).
- **Does not manage the Terraform state bucket** — bootstrap is a one-time shell script ([scripts/bootstrap-tfstate.sh](scripts/bootstrap-tfstate.sh)), documented but not automated.

## Stacks

Numbered by dependency. Each stack is independent and ships the standard 9 files (`versions.tf`, `backend.tf`, `providers.tf`, `variables.tf`, `locals.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars.example`, `README.md`).

| Stack | Purpose | Modes honoured | Status in v0.1.0 |
|---|---|---|---|
| `00-org-baseline` | References the GCP Organization + essential contacts at org scope | `existing` / `create` | Shipped |
| `10-folders` | Provisions the folder tree (`Platform` / `LandingZones` / `Sandbox`) | `existing` / `create` | Shipped |
| `20-projects` | Platform project factory (`plogs`, `pmgm`, `piam`, `pdns`, `pingress`, `sandbox`) via the shared `projects` module | `existing` / `create` | Shipped |
| `30-org-policies` | Curated `google_org_policy_policy` catalogue with `enable_X` switches (dry-run by default) | Any mode | Planned v0.2.0 |
| `40-org-logging` | `google_logging_organization_sink` → `plogs`, writer identity IAM | Any mode | Planned v0.2.0 |
| `50-org-iam` | Org-level IAM bindings + break-glass roles + essential contacts | Any mode | Planned v0.3.0 |
| `60-tags` | Org-scoped Resource Manager tag keys / values | Any mode (opt-in) | Planned v0.3.0 |

## The two organization modes

Every stack honours a global `organization_mode` variable with two valid values:

- **`existing`** (default) — every resource is a data source. Terraform reads the pre-existing folders / projects and re-exports them via the contract. Zero resources created. Safest starting point; use it against any customer Org that already has structure.
- **`create`** — vanilla Terraform provisions folders + platform projects. Requires `roles/resourcemanager.folderCreator` on the Org and `roles/resourcemanager.projectCreator` + `roles/billing.user` on the billing account. **Project `deletion_protection = true` by default** — a `terraform destroy` on stack `20-projects` will refuse to run.

The two modes produce the **same output shape** (see [docs/contract.md](docs/contract.md)) so downstream repos stay agnostic.

**Why no `control_tower` equivalent**: GCP has no service that stands as a peer to Terraform in the way AWS Control Tower does. Google Cloud Foundation Fabric is a Terraform blueprint set (i.e. code you consume), not a runtime that owns state alongside your own. If Fabric integration becomes a hard requirement, it will land as a `blueprint` mode in a future minor version. See [ADR-0001](docs/adr/0001-two-modes-only-existing-and-create.md).

## The LZ / baseline contract

Any downstream repo consumes this one via `terraform_remote_state`. The output surface is small and stable:

```hcl
output "organization_id"          # e.g. "123456789012"
output "organization_domain"      # e.g. "example.com"
output "billing_account_id"       # e.g. "01ABCD-234567-EFGH89"
output "folder_ids"               # { Platform="folders/111...", LandingZones="folders/222...", Sandbox="folders/333..." }
output "platform_project_ids"     # { plogs="gcp0-prj-emp-plogs-01", pmgm="...", piam="...", pdns="...", pingress="...", sandbox="..." }
output "platform_project_numbers" # { plogs="123456789", ... }
output "mode"                     # "existing" | "create"
```

Full spec — including planned outputs for stacks `30`-`60` — in [docs/contract.md](docs/contract.md).

## Repository layout

```
├── docs/
│   ├── architecture.md          Tier model, why hierarchy != baseline, per-stack rationale
│   ├── conventions.md           Naming, defaults, modes, style
│   ├── contract.md              Output contract consumed by baselines + LZs
│   └── adr/                     Architecture Decision Records (MADR-lite)
├── scripts/
│   └── bootstrap-tfstate.sh     One-time GCS bucket bootstrap for Terraform state
└── stacks/
    ├── 00-org-baseline/         Shipped in v0.1.0
    ├── 10-folders/              Shipped in v0.1.0
    ├── 20-projects/             Shipped in v0.1.0
    ├── 30-org-policies/         Planned v0.2.0
    ├── 40-org-logging/          Planned v0.2.0
    ├── 50-org-iam/              Planned v0.3.0
    └── 60-tags/                 Planned v0.3.0
```

No `modules/` folder — reusable primitives live in [`shared-modules/terraform-gcp-modules`](../../shared-modules/terraform-gcp-modules/) (currently consumed: the `projects` module, pinned at `v0.1.0`).

## The state backend bootstrap

Tier 0 owns the platform projects, but Terraform state has to live in a GCS bucket that itself lives in a project. Classic chicken-and-egg. The convention:

- **State bucket lives in a dedicated `ptfstate` project** in the same billing account as the rest of the platform.
- Bootstrap the project + bucket **one time, outside Terraform**, using [`scripts/bootstrap-tfstate.sh`](scripts/bootstrap-tfstate.sh). Run once per Organization, never again.
- Every stack in every Tier writes state to that same bucket, discriminated by `prefix`. Cross-project access is via the executing identity's org-level IAM.

The script is idempotent (safe to re-run) but is not part of any Terraform apply flow — pretending it is hides an important operational fact.

## Deployment order

```bash
# 0. One-time (run once per Organization, from a user with roles/resourcemanager.organizationAdmin):
./scripts/bootstrap-tfstate.sh

# 1. Tier 0 stacks — this repo, apply in numeric order.
terraform -chdir=stacks/00-org-baseline init && terraform -chdir=stacks/00-org-baseline apply
terraform -chdir=stacks/10-folders       init && terraform -chdir=stacks/10-folders       apply
terraform -chdir=stacks/20-projects      init && terraform -chdir=stacks/20-projects      apply

# 2. Tier 1 baselines — deploy INTO the platform projects created above.
terraform -chdir=../../baseline-projects/gcp-observability-baseline/stacks/... init && apply
# (etc: dns, identity, security baselines)

# 3. Tier 2 landing zone — consume Tier 0 via terraform_remote_state.
terraform -chdir=../../landing-zones/gcp-lz-fortinet-multiproject/stacks/00-network-core init && apply
```

## Consumer example

A landing zone reads Tier 0 like this:

```hcl
data "terraform_remote_state" "org" {
  backend = "gcs"
  config = {
    bucket = var.org_state_bucket
    prefix = "gcp-org-hierarchy/20-projects"
  }
}

locals {
  log_project     = data.terraform_remote_state.org.outputs.platform_project_ids.plogs
  organization_id = data.terraform_remote_state.org.outputs.organization_id
}
```

The prefix always points to the specific Tier 0 stack that publishes the needed output. Multiple `data "terraform_remote_state"` blocks are fine when a consumer needs outputs from several Tier 0 stacks.

## Status

Initial release (v0.1.0). Stacks `00-org-baseline`, `10-folders`, and `20-projects` shipped. Stacks `30`-`60` scaffolded with placeholder READMEs; content lands in v0.2.0 / v0.3.0.

## License

[Apache License 2.0](LICENSE). Copyright &copy; 2026 Ismael Cruz.

## Author

Ismael Cruz &mdash; cloud &amp; networking architect. AWS / GCP / Azure landing zones, hierarchy, and security guardrails.
