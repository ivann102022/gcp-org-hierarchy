<!--
File:        README.md
Author:      Ismael Cruz
Version:     0.2.0
Description: Entry point for gcp-org-hierarchy — Tier 0 of the GCP
             stacked-repo taxonomy. Anchors the portfolio to the pre-existing
             GCP Organization and administers the folder hierarchy, platform
             project factory, org policies, org-level logging sink, and
             org-scope IAM. Every GCP baseline (baseline-projects/gcp-*-baseline)
             and landing zone (landing-zones/gcp-lz-*) consumes this via
             terraform_remote_state.
-->

# GCP Organization Hierarchy

**Tier 0** of the GCP stacked-repo taxonomy. **Anchors** the portfolio to the pre-existing GCP Organization (which arrives with your Cloud Identity / Google Workspace tenant &mdash; Terraform cannot create it) and administers the org-scope elements Google leaves to you: the folder hierarchy, the platform project factory (`plogs`, `pmgm`, `piam`, `pdns`, `pingress`, `sandbox`), organization policies, the organization-level log sink, org-scope IAM bindings, essential contacts, and (optionally) resource-manager tag keys/values.

Every GCP Landing Zone (`landing-zones/gcp-lz-*`) and every GCP baseline (`baseline-projects/gcp-*-baseline`) consumes the outputs of this repo via `terraform_remote_state`. Swap the LZ, swap the baseline; keep the hierarchy.

## The anchor + baseline pattern (stack `00-org-baseline`)

The name of `00-org-baseline` encodes two active responsibilities, not a passive lookup:

1. **Anchor** &mdash; publish `organization_id`, `organization_name`, `organization_domain`, and `billing_account_id` as **contractual facts** every downstream stack and repo consumes. Downstream never re-discovers the Org; they read this contract.
2. **Baseline** &mdash; provision the minimum org-scope elements administered from apply #1 that do not belong to any specific discipline. Today: `google_essential_contacts_contact`.

This is the same conceptual role the AWS sibling `aws-org-hierarchy/00-org-baseline` plays &mdash; in AWS the anchor is a `create` (Organization does not exist); in GCP the anchor is a `data` (Organization pre-exists). Same responsibility, different implementation because of CSP API constraints.

**Content rule** (guardrail against `00-org-baseline` becoming a catch-all): a candidate belongs here only if it is (1) org-scope, (2) established at apply #1, AND (3) does not belong to any discipline (Policies / Logging / IAM / Tags). If it fits a discipline, it goes to stacks `30`/`40`/`50`/`60`, even if org-scope. See [ADR-0007](docs/adr/0007-content-rule-for-org-baseline.md).

## What this repo does NOT do

- **Does not create the Organization itself** &mdash; the Organization is a Google Workspace / Cloud Identity artefact. Stack `00-org-baseline` **anchors** to it (see above).
- **Does not deploy VPCs, NAT, firewalls, or FortiGates** &mdash; that's the landing zone (Tier 2). The perimeter appliance lives in `pnet-hub` (LZ-owned). Public ingress bypasses the perimeter appliance by design &mdash; see [ADR-0008](docs/adr/0008-ingress-bypasses-perimeter-appliance.md).
- **Does not enable SCC, Cloud Logging dashboards, DNS zones, or KMS keys inside `plogs` / `pmgm` / `pdns`** &mdash; that's the corresponding Tier 1 baseline. This repo only creates the projects (containers); the baselines fill them.
- **Does not configure Workforce Identity Federation** &mdash; that lives in `gcp-identity-baseline` (Tier 1). Rationale in [ADR-0004](docs/adr/0004-no-workforce-identity-federation-here.md).
- **Does not manage the Terraform state bucket** &mdash; bootstrap is a one-time shell script ([scripts/bootstrap-tfstate.sh](scripts/bootstrap-tfstate.sh)), documented but not automated.

## Stacks

Numbered by dependency. Each stack is independent and ships the standard 9 files (`versions.tf`, `backend.tf`, `providers.tf`, `variables.tf`, `locals.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars.example`, `README.md`).

| Stack | Purpose | Modes honoured | Status |
|---|---|---|---|
| `00-org-baseline` | Anchor + baseline (see section above): references the GCP Organization + essential contacts at org scope | `existing` / `create` | Shipped v0.1.0 |
| `10-folders` | Provisions the folder tree with depth up to 3 (see [Folder tree](#folder-tree) below) | `existing` / `create` | Shipped v0.1.0 · v0.2.0 refactor pending |
| `20-projects` | Platform project factory (`plogs`, `pmgm`, `piam`, `pdns`, `pingress`, `sandbox`) with 1:1 home folder mapping via the shared `projects` module | `existing` / `create` | Shipped v0.1.0 · v0.2.0 refactor pending |
| `30-org-policies` | Curated `google_org_policy_policy` catalogue with `enable_X` switches (dry-run by default) | Any mode | Planned v0.3.0 |
| `40-org-logging` | `google_logging_organization_sink` &rarr; `plogs`, writer identity IAM | Any mode | Planned v0.3.0 |
| `50-org-iam` | Org-level IAM bindings + break-glass roles | Any mode | Planned v0.4.0 |
| `60-tags` | Org-scoped Resource Manager tag keys / values | Any mode (opt-in) | Planned v0.4.0 |

## Folder tree (v0.2.0)

Reference tree provisioned by `10-folders` with defaults. Every sub-folder set is configurable; PascalCase display names throughout.

```
Organization (emp.com)
├── Platform                       [root]
│   ├── Logs                       # home of plogs             — ADR-0005
│   ├── Management                 # home of pmgm              — ADR-0005
│   ├── IAM                        # home of piam              — ADR-0005
│   ├── DNS                        # home of pdns              — ADR-0005
│   └── Ingress                    # home of pingress          — ADR-0005
├── LandingZones                   [root]
│   ├── HUB                        # home of pnet-hub (LZ)     — ADR-0006 (flat)
│   ├── HostPrj                    # env-split                 — ADR-0006
│   │   ├── PRO                    # home of pnet-pro (LZ)
│   │   ├── PRE                    # home of pnet-pre (LZ)
│   │   └── DEV                    # home of pnet-dev (LZ)
│   └── ServicePrj                 # env-split                 — ADR-0006
│       ├── PRO                    # home of srv-pro (LZ)
│       ├── PRE                    # home of srv-pre (LZ)
│       └── DEV                    # home of srv-dev (LZ)
└── Sandbox                        [root, flat]                # home of sandbox
```

- **`Platform` has one folder per platform project** (1:1) &mdash; enables per-project IAM scoping and per-folder org policies. See [ADR-0005](docs/adr/0005-folder-per-platform-project.md).
- **`LandingZones` has three second-level children** &mdash; `HUB` (flat), `HostPrj` and `ServicePrj` (both env-split by `PRO`/`PRE`/`DEV`). Encodes the Shared VPC host-vs-service lifecycle split. See [ADR-0006](docs/adr/0006-landing-zones-hostprj-serviceprj-env-split.md).
- **Composite keys for grandchildren**: `PRO`/`PRE`/`DEV` reappear under both `HostPrj` and `ServicePrj`. Terraform keys them as `HostPrj-PRO`, `ServicePrj-DEV`, etc. (GCP display-name uniqueness is per-parent).

## The two organization modes

Every stack honours a global `organization_mode` variable with two valid values:

- **`existing`** (default) &mdash; every resource is a data source. Terraform reads the pre-existing folders / projects and re-exports them via the contract. Zero resources created. Safest starting point; use it against any customer Org that already has structure.
- **`create`** &mdash; vanilla Terraform provisions folders + platform projects. Requires `roles/resourcemanager.folderCreator` on the Org and `roles/resourcemanager.projectCreator` + `roles/billing.user` on the billing account. **Project `deletion_policy = "PREVENT"` by default** &mdash; a `terraform destroy` on stack `20-projects` will refuse to run.

Both modes leave stack `00-org-baseline` as an **anchor + baseline** (the anchor is always a data source since the Organization is a Cloud Identity artefact). "Create" in this repo means create *folders + projects + policies + org-sink* &mdash; never the Organization itself.

The two modes produce the **same output shape** (see [docs/contract.md](docs/contract.md)) so downstream repos stay agnostic.

**Why no `control_tower` equivalent**: GCP has no service that stands as a peer to Terraform in the way AWS Control Tower does. Google Cloud Foundation Fabric is a Terraform blueprint set (i.e. code you consume), not a runtime that owns state alongside your own. If Fabric integration becomes a hard requirement, it will land as a `blueprint` mode in a future minor version. See [ADR-0001](docs/adr/0001-two-modes-only-existing-and-create.md).

## The LZ / baseline contract

Any downstream repo consumes this one via `terraform_remote_state`. The output surface is small and stable:

```hcl
output "organization_id"          # e.g. "123456789012"
output "organization_name"        # "organizations/123456789012"
output "organization_domain"      # "example.com"
output "billing_account_id"       # "01ABCD-234567-EFGH89"
output "folder_ids"               # { Platform="folders/...", Logs="folders/...", HostPrj-PRO="folders/...", ... }
output "root_folder_ids"          # subset — Platform / LandingZones / Sandbox only
output "platform_child_folder_ids"    # subset — Logs / Management / IAM / DNS / Ingress
output "landing_zone_env_folder_ids"  # subset — HostPrj-PRO / ServicePrj-DEV / ...
output "platform_project_ids"     # { plogs="gcp0-prj-emp-plogs-01", pmgm="...", piam="...", pdns="...", pingress="...", sandbox="..." }
output "platform_project_numbers" # { plogs="123456789", ... }
output "platform_project_home_folders"  # { plogs="Logs", pmgm="Management", ... } — v0.2.0
output "mode"                     # "existing" | "create"
```

Full spec &mdash; including planned outputs for stacks `30`-`60` &mdash; in [docs/contract.md](docs/contract.md).

## Repository layout

```
├── docs/
│   ├── architecture.md          Tier model, anchor+baseline framing, folder tree, per-stack rationale
│   ├── conventions.md           Naming, defaults, modes, style
│   ├── contract.md              Output contract consumed by baselines + LZs
│   └── adr/                     Architecture Decision Records (MADR-lite, 8 in v0.2.0)
├── scripts/
│   └── bootstrap-tfstate.sh     One-time GCS bucket bootstrap for Terraform state
└── stacks/
    ├── 00-org-baseline/         Shipped (v0.1.0)
    ├── 10-folders/              Shipped v0.1.0 · v0.2.0 refactor (depth 3 + composite keys)
    ├── 20-projects/             Shipped v0.1.0 · v0.2.0 refactor (home folder mapping)
    ├── 30-org-policies/         Planned v0.3.0
    ├── 40-org-logging/          Planned v0.3.0
    ├── 50-org-iam/              Planned v0.4.0
    └── 60-tags/                 Planned v0.4.0
```

No `modules/` folder &mdash; reusable primitives live in [`shared-modules/terraform-gcp-modules`](../../shared-modules/terraform-gcp-modules/) (currently consumed: the `projects` module, pinned at `v0.1.0`).

## The state backend bootstrap

Tier 0 owns the platform projects, but Terraform state has to live in a GCS bucket that itself lives in a project. Classic chicken-and-egg. The convention:

- **State bucket lives in a dedicated `ptfstate` project** in the same billing account as the rest of the platform.
- Bootstrap the project + bucket **one time, outside Terraform**, using [`scripts/bootstrap-tfstate.sh`](scripts/bootstrap-tfstate.sh). Run once per Organization, never again.
- Every stack in every Tier writes state to that same bucket, discriminated by `prefix`. Cross-project access is via the executing identity's org-level IAM.

The script is idempotent (safe to re-run) but is not part of any Terraform apply flow &mdash; pretending it is hides an important operational fact.

## Deployment order

```bash
# 0. One-time (run once per Organization, from a user with roles/resourcemanager.organizationAdmin):
./scripts/bootstrap-tfstate.sh

# 1. Tier 0 stacks — this repo, apply in numeric order.
terraform -chdir=stacks/00-org-baseline init && terraform -chdir=stacks/00-org-baseline apply
terraform -chdir=stacks/10-folders       init && terraform -chdir=stacks/10-folders       apply
terraform -chdir=stacks/20-projects      init && terraform -chdir=stacks/20-projects      apply

# 2. Tier 1 baselines — deploy INTO the platform projects created above.
terraform -chdir=../../baseline-projects/gcp-dns-baseline/stacks/00-dns-zones init && apply
terraform -chdir=../../baseline-projects/gcp-observability-baseline/stacks/00-log-storage init && apply
# (etc: identity, security baselines when they land)

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

- **v0.1.0** shipped. Stacks `00-org-baseline`, `10-folders`, `20-projects` populated. Stacks `30`-`60` scaffolded with placeholder READMEs.
- **v0.2.0** working tree contains: folder tree extended to depth 3 with 1:1 platform children (`Logs`/`Management`/`IAM`/`DNS`/`Ingress`) + `HostPrj`/`ServicePrj` env-split under `LandingZones` (ADR-0005, ADR-0006); role &rarr; home folder mapping in `20-projects` with `moved` blocks for in-place state migration; anchor + baseline framing formalised across docs + ADR-0007 (content rule); ADR-0008 (ingress bypasses perimeter appliance).

## License

[Apache License 2.0](LICENSE). Copyright &copy; 2026 Ismael Cruz.

## Author

Ismael Cruz &mdash; cloud &amp; networking architect. AWS / GCP / Azure landing zones, hierarchy, and security guardrails.
