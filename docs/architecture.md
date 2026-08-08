<!--
File:        docs/architecture.md
Author:      Ismael Cruz
Version:     0.3.0
Description: Architecture reference for gcp-org-hierarchy — the layered
             repo model in GCP, why hierarchy is Tier 0, the anchor + baseline
             framing for stack 00, the v0.2.0 folder tree (1:1 platform
             children + HostPrj/ServicePrj env-split under LandingZones),
             the layered segmentation principle (v0.3.0), and per-stack
             design rationale. Non-obvious decisions are extracted to ADRs
             under docs/adr/. Framework alignment and maturity roadmap in
             docs/security/.
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

Each tier knows only the one below via a documented contract. In GCP, Tier 0 exists because Google provisions the Organization and may apply baseline security organization policies (the "secure by default" set introduced in 2024), but the customer remains responsible for designing and administering the target folder hierarchy, the project structure, and the organization-policy posture on top of that baseline. This is different from AWS (where Tier 0 also creates the Organization itself) and closer to Azure (where the tenant arrives but Management Groups must be designed and provisioned).

Cross-CSP contrast summarised:

| CSP | How the "top of the tree" arrives |
|---|---|
| **AWS** | You create it. `aws_organizations_organization`, OUs, accounts. No shortcut. |
| **GCP** | Comes with Google Workspace / Cloud Identity. **Folders are optional structure inside it, but every enterprise wants them.** |
| **Azure** | Comes with the Entra ID tenant. Management Groups are optional structure inside it. |

## Layered segmentation &mdash; hierarchy is the first line

Every non-trivial decision in this repo is grounded in a **three-scale segmentation model**. Segmentation is not delegated exclusively to the network:

- **Scale 1 &mdash; Resource Hierarchy** (Folders + Projects). Question: *which administrative, security and governance domains do I want to separate?* This is where HostPrj/ServicePrj, PRO/PRE/DEV, and 1:1 folder-per-platform-project live. IAM inheritance through the folder tree is the primary control surface.
- **Scale 2 &mdash; VPC** (VPC / Shared VPC / peering / NCC). Question: *which connectivity domains do I want to create?* HUB perimeter lives here.
- **Scale 3 &mdash; Distributed Firewall** (VPC firewall rules, hierarchical firewall policies, tag-based rules). Question: *even if reachability exists, who is authorized to talk to whom?* GCP's implicit-deny model at this scale is what makes single-HUB defensible &mdash; the perimeter appliance is reserved for cross-domain transit, not for every east-west flow.

Full principle in [ADR-0009](adr/0009-layered-segmentation-hierarchy-first.md). Its two direct consequences in this repo are documented in [ADR-0005](adr/0005-folder-per-platform-project.md) (Scale 1 for platform tier) and [ADR-0006](adr/0006-landing-zones-hostprj-serviceprj-env-split.md) (Scale 1 for landing zones). The single-HUB decision in [ADR-0010](adr/0010-single-shared-perimeter-hub.md) is defensible *because* Scale 3 handles microsegmentation.

Framework alignment for every decision is consolidated in [`security/control-mapping.md`](security/control-mapping.md); per-decision maturity paths (current / enhanced / high-isolation) in [`security/maturity.md`](security/maturity.md).

## Cloud Billing Account is outside the Resource Manager tree

Worth flagging explicitly because `billing_account_id` appears prominently in this repo's contract and a reader might infer it is part of the hierarchy.

The Cloud Billing Account is **not** part of the Resource Manager tree (`Organization → Folder → Project`). It is a separate resource (`billingAccounts/<id>`) with a **billing relationship** to Projects, expressed via `google_project.billing_account`. A single Billing Account may pay for Projects across multiple Organizations, which makes it structurally orthogonal to the hierarchy &mdash; the Resource Manager tree is per-Organization; the Billing Account can span across.

Throughout this repo:

- **`billing_account_id` is a contract attribute**, not a hierarchy node. Stack `00-org-baseline` publishes it as one of the "anchor" facts so downstream stacks (starting with `20-projects`) can link the Platform Projects to the correct Billing Account via `google_project.billing_account`.
- **`roles/billing.user` on the Billing Account** is a distinct IAM scope from `roles/resourcemanager.*` on Org / Folder / Project scopes. Stack `20-projects` requires both because it creates Projects (Resource Manager scope) AND attaches them to the Billing Account (Billing scope).
- **The folder tree diagrams throughout this repo** do not depict the Billing Account. It sits alongside the hierarchy, not inside it.

## Stack `00-org-baseline`: the anchor + baseline pattern

The name of stack `00-org-baseline` is deliberate and encodes two active responsibilities, not one passive lookup:

1. **Anchor** &mdash; establish the canonical point of reference for the portfolio to the pre-existing GCP Organization. The stack publishes `organization_id`, `organization_name`, `organization_domain`, and `billing_account_id` as **contractual facts** that every downstream stack and repo consumes via `terraform_remote_state`. Downstream never re-discovers the Org; they read this contract. That publication is active work even though the underlying `google_organization` is a data source.

2. **Baseline** &mdash; provision the **minimal set of org-scope elements administered from apply #1** that do not belong to any specific discipline. Today that set is just `google_essential_contacts_contact` (security / billing / technical notifications at Org scope). It's small on purpose &mdash; see the content rule below.

Same role as the AWS sibling `aws-org-hierarchy/00-org-baseline`: **anchor + baseline**. In AWS the anchor is a `create` (Organization does not exist); in GCP the anchor is a `data` (Organization pre-exists). The **conceptual responsibility is identical**; only the implementation differs because of CSP API constraints.

### Content rule for stack `00-org-baseline`

A candidate belongs in this stack **only if it meets all three criteria**:

1. **Org-scope** &mdash; its natural scope is the Organization, not a folder or project.
2. **Fundacional** &mdash; established at apply #1, not at apply #N.
3. **Not a discipline** &mdash; does not fall cleanly under Policies (30), Logging (40), IAM (50), or Tags (60), *even if org-scope*.

The third criterion is the guardrail. Without it, "org-scope + fundacional" alone would slowly turn `00-org-baseline` into a catch-all and erode the reason the other stacks exist. See [ADR-0007](adr/0007-content-rule-for-org-baseline.md) for the full test with worked examples.

## The v0.2.0 folder tree

```
Organization (emp.com)
├── Platform                       [root]
│   ├── Logs                       [child]        → home of plogs
│   ├── Management                 [child]        → home of pmgm
│   ├── IAM                        [child]        → home of piam
│   ├── DNS                        [child]        → home of pdns
│   └── Ingress                    [child]        → home of pingress
├── LandingZones                   [root]
│   ├── HUB                        [child, flat]         → home of pnet-hub (LZ-owned)
│   ├── HostPrj                    [child, env-split]
│   │   ├── PRO                    [grandchild]          → home of pnet-pro (LZ-owned)
│   │   ├── PRE                    [grandchild]          → home of pnet-pre (LZ-owned)
│   │   └── DEV                    [grandchild]          → home of pnet-dev (LZ-owned)
│   └── ServicePrj                 [child, env-split]
│       ├── PRO                    [grandchild]          → home of srv-pro (LZ-owned)
│       ├── PRE                    [grandchild]          → home of srv-pre (LZ-owned)
│       └── DEV                    [grandchild]          → home of srv-dev (LZ-owned)
└── Sandbox                        [root, flat]          → home of sandbox
```

Design decisions embedded in this shape:

- **`Platform` has one folder per platform project (1:1)** &mdash; not grouped by discipline. Enables granular IAM scoping (`roles/dns.admin` on `DNS` folder applies only to `pdns`), per-folder org policies, and clean audit surfaces. See [ADR-0005](adr/0005-folder-per-platform-project.md).
- **`LandingZones` has three second-level children** &mdash; `HUB` (flat) plus `HostPrj` and `ServicePrj` (both env-split). The split encodes three concurrent dimensions at the folder level: **ownership** (Network+Security teams operate HostPrj; Systems+Applications teams operate ServicePrj), **policy inheritance** (network guardrails inherited on HostPrj, workload guardrails on ServicePrj), and **lifecycle** (Shared VPC changes rarely, workloads constantly). Function/ownership is deliberately the first frontier under `LandingZones`; environment (PRO/PRE/DEV) is the second. See [ADR-0006](adr/0006-landing-zones-hostprj-serviceprj-env-split.md).
- **`Sandbox` stays flat** &mdash; a single sandbox project by default; expand with `custom_folders` if per-team sandboxes are needed.

Depth-3 grandchildren under `HostPrj` and `ServicePrj` use composite keys (`HostPrj-PRO`, `ServicePrj-DEV`, ...) in Terraform's flat map because display-name uniqueness in GCP is per-parent, not global (see [ADR-0006](adr/0006-landing-zones-hostprj-serviceprj-env-split.md#composite-keys)).

## Why platform projects live here, not in each LZ

Superficially, the platform projects (`plogs`, `pmgm`, `piam`, `pdns`, `pingress`, `sandbox`) could be created by whichever LZ deploys first &mdash; the GCP LZs even ship a `create_projects = true` mode for that. In practice, that pattern collapses when a second LZ appears: the two LZs either fight for ownership of the same project IDs or drift into inconsistent naming.

Making Tier 0 the sole owner:

- Every LZ consumes the same `platform_project_ids` map. Zero drift.
- Every baseline knows where to deploy (`plogs` for observability, `pmgm` for KMS, `pdns` for Cloud DNS, ...).
- Projects can move between folders (`google_project.folder_id`) without needing to reprovision.
- The LZ's `create_projects = true` mode remains as a fallback for greenfield / demo deployments where a full Tier 0 is not being run.

Full rationale in [ADR-0002](adr/0002-platform-projects-here-not-in-lz.md).

## Why the org log sink lives here, not in observability-baseline

`google_logging_organization_sink` is an **org-scope resource** &mdash; creating it requires `roles/logging.configWriter` at the Organization level. Observability-baseline is written to run inside a single project (`plogs`) with project-scope permissions. Putting the org sink in observability-baseline would force the baseline to hold org-level rights it does not otherwise need.

Split:

- **Tier 0 (this repo, stack `40-org-logging`)** creates the org sink and points it at `plogs`. Creates the writer-identity IAM binding on `plogs`.
- **Tier 1 (`gcp-observability-baseline`)** operates *inside* `plogs`: log buckets, retention policies, exclusions, exports to BigQuery, dashboards, alerts.

Full rationale in [ADR-0003](adr/0003-org-sink-in-tier0-not-obs-baseline.md).

## Why Workforce Identity Federation is not here

WIF is often lumped into "org hierarchy" material because it's org-scope in name. It is not:

- WIF pools / providers can be created at the project scope (`google_iam_workforce_pool` targets a workforce federation project &mdash; typically `piam`).
- WIF is intimately coupled to group-based IAM patterns, custom roles, break-glass procedures &mdash; all of which are **identity discipline** (Tier 1), not hierarchy discipline (Tier 0).
- Coupling WIF to Tier 0 would force every hierarchy change to redeploy identity infrastructure. Wrong blast-radius alignment.

Split: this repo creates `piam` (the project). `gcp-identity-baseline` provisions WIF pools, groups, custom roles, and break-glass patterns inside `piam`. Full rationale in [ADR-0004](adr/0004-no-workforce-identity-federation-here.md).

## Why public ingress bypasses the perimeter appliance

The Tier 2 LZ deploys a FortiGate perimeter appliance in `pnet-hub` that handles **egress** (workload-initiated outbound traffic) and **east-west** (inter-tenant, inter-environment) inspection. It does **not** sit in the path of public **ingress** traffic.

Public ingress terminates at Google's edge via Global External Load Balancers + Cloud Armor + WAF, all provisioned in the `pingress` project (VPC materialised by the future `gcp-ingress-baseline`). From `pingress`, traffic reaches backend services via Private Service Connect / internal LB paths &mdash; not via the FortiGate.

Rationale:
- Google's edge already provides DDoS protection, TLS termination, and WAF at scale &mdash; forcing traffic through a self-managed FortiGate afterward would add latency and a stateful chokepoint without security benefit.
- Global External LBs cannot use a self-managed NVA as a backend; the architecture is prescriptive.
- Consolidating public ingress into `pingress` (with its own Internet path) keeps the FortiGate focused on the traffic it can meaningfully inspect (egress + east-west).

Full rationale in [ADR-0008](adr/0008-ingress-bypasses-perimeter-appliance.md).

## The two organization modes

Every stack in this repo honours `organization_mode` with two values:

| Mode | Behaviour | Use case |
|---|---|---|
| `existing` (default) | Every resource is a data source. Terraform reads pre-existing folders / projects and re-exports them via the contract. Zero side effects. | Any pre-existing customer Org &mdash; bring-your-own. |
| `create` | Vanilla Terraform provisions folders + platform projects + org-policies + org-sink. Full IaC control. | Greenfield deployment. |

In both modes, stack `00-org-baseline` remains an **anchor + baseline** (see the section above) &mdash; the `create` mode of Tier 0 refers to *folders + projects + policies + org-sink*, not the Organization itself.

There is no `blueprint` or `control_tower` mode in v0.2.0. Google Cloud Foundation Fabric is Terraform code you consume, not a runtime peer of Terraform in the way AWS Control Tower is. If Fabric integration becomes a hard requirement, it lands as a future `blueprint` mode. Full rationale in [ADR-0001](adr/0001-two-modes-only-existing-and-create.md).

The two modes produce the **same output shape** (see [contract.md](contract.md)) so downstream consumers stay agnostic.

## Stack-by-stack

### `00-org-baseline`

- **Role**: **anchor + baseline** (see the section above). Publishes contract facts, provisions minimal org-scope elements not owned by any discipline.
- **Owns**:
  - `data "google_organization" "this"` &mdash; looked up by `var.organization_domain`. **Always a data source**: GCP does not allow Terraform to create Organizations (they arrive with your Google Workspace / Cloud Identity tenant). See [ADR-0001](adr/0001-two-modes-only-existing-and-create.md).
  - `google_essential_contacts_contact` per entry in `var.essential_contacts` &mdash; only when `var.enable_essential_contacts = true`. Meets the [content rule](#content-rule-for-stack-00-org-baseline): org-scope + fundacional + no-discipline.
- **Inputs of note**: `organization_domain` (used to look up the Org), `billing_account_id` (passed through to `20-projects`), `essential_contacts` (map of category &rarr; email list).
- **Outputs**: `organization_id`, `organization_name`, `organization_domain`, `billing_account_id`, `mode`.

### `10-folders`

- **Owns**: the v0.2.0 folder tree (three depths). Reference set defaults reproduce the architecture diagrams:
  - Roots: `Platform`, `LandingZones`, `Sandbox`.
  - Children under `Platform`: `Logs`, `Management`, `IAM`, `DNS`, `Ingress` (1:1 per platform project).
  - Children under `LandingZones`: `HUB` (flat), `HostPrj` and `ServicePrj` (env-split).
  - Grandchildren under `HostPrj` and `ServicePrj`: `PRO`, `PRE`, `DEV` (default env set).
- **Modes**: `create` provisions via three resource blocks (roots / children / grandchildren); `existing` reads via `var.existing_folder_ids` (operator provides the map).

### `20-projects`

- **Owns**: the platform projects, provisioned via the shared `projects` module (`git::…/terraform-gcp-modules.git//modules/projects?ref=v0.1.0`) instantiated **once per home folder** via `for_each`.
- **Default role &rarr; folder mapping** (`var.platform_project_home_folder`):

  | Role | Home folder (v0.2.0 default) | Project ID |
  |---|---|---|
  | `plogs` | `Logs` | `gcp0-prj-emp-plogs-01` |
  | `pmgm` | `Management` | `gcp0-prj-emp-pmgm-01` |
  | `piam` | `IAM` | `gcp0-prj-emp-piam-01` |
  | `pdns` | `DNS` | `gcp0-prj-emp-pdns-01` |
  | `pingress` | `Ingress` | `gcp0-prj-emp-pingress-01` |
  | `sandbox` | `Sandbox` | `gcp0-prj-emp-sandbox-01` |

- **`deletion_policy = "PREVENT"`** on every platform project (provider &ge; v6 default). Accidental `terraform destroy` fails loud.
- **Modes**: `create` provisions; `existing` reads by project ID.
- **State migration from v0.1.0**: shipped via `moved` blocks in [`main.tf`](../stacks/20-projects/main.tf); folder reparent is an in-place `google_project.folder_id` update, no recreation.

### `30-org-policies`

- **Owns**: `google_org_policy_policy` at Org scope, curated catalog of 8 policies with per-policy `enable_X` switches.
- **All policies default to `dry_run = true`** &mdash; surfaces violations in the audit log without blocking. Operator flips individual policies to enforce via `enforce_overrides` after validation.
- **Catalog**: `disable_sa_keys`, `require_oslogin`, `deny_external_ip`, `prevent_public_storage`, `restrict_sql_public_ip`, `allowed_policy_member_domains`, `trusted_image_projects`, `resource_locations`. Additional constraints via `custom_org_policies`.
- Full rationale in [ADR-0011](adr/0011-curated-org-policy-catalog.md).

### `40-org-logging`

- **Owns**: `google_logging_organization_sink` at Org scope (with `include_children = true` by default so every project in every folder is captured); `google_project_iam_member` granting the sink's writer identity `roles/logging.bucketWriter` on `plogs`.
- **Filter default `""`** (all logs); override for cost management. **Destination default `plogs`/`_Default` log bucket**; override to custom bucket from `gcp-observability-baseline/00-log-storage` once that is applied.
- **Downstream**: `gcp-observability-baseline` consumes `log_sink_writer_identity` and destination. Obs-baseline's deferred-integration hook (created before this stack existed) is superseded by this stack's binding &mdash; recommended migration: set `org_sink_writer_identity = ""` in obs-baseline tfvars.
- Full rationale in [ADR-0003](adr/0003-org-sink-in-tier0-not-obs-baseline.md) (why here) and [ADR-0012](adr/0012-org-sink-design.md) (design choices).

### `50-org-iam`

- **Owns**: `google_organization_iam_member` for a curated set of org-scope roles: Org Admin, Project Creator, Billing Admin, Security Admin, Logging Admin, Org Policy Admin, Org Viewer, and a dedicated **break-glass** binding separated from `org_admins` for alerting granularity.
- Uses `google_organization_iam_member` (per-member) rather than `google_organization_iam_binding` (authoritative per-role) to avoid stomping on bindings created outside Terraform.
- **Excludes** Workforce Identity Federation (see [ADR-0004](adr/0004-no-workforce-identity-federation-here.md)) and identity-baseline's custom roles.
- Break-glass model in [ADR-0013](adr/0013-break-glass-user-model.md).

### `60-tags`

- **Opt-in** (`enable_tags = false` default) because tagging introduces ongoing operational cost only worth it when downstream consumers actually bind tags.
- **Owns**: `google_tags_tag_key` + `google_tags_tag_value` at Org scope with `purpose = "GCE_FIREWALL"` for maximum consumer compatibility.
- **Reference catalog**: `environment`, `data-classification`, `cost-center` (opt-in), `owner` (opt-in). Additional keys via `custom_tag_keys`.
- Values for `environment` match the folder tree naming (lowercased for GCP tag validation): `prod`, `preprod`, `dev`.
- Full rationale in [ADR-0014](adr/0014-tag-catalog-choice.md).

## Apply order

Within this repo:

```
00-org-baseline → 10-folders → 20-projects → 30-org-policies → 40-org-logging → 50-org-iam → 60-tags
```

All seven stacks shipped as of v0.4.0. Stacks 30/40/50/60 are independently applyable; the order above reflects dependency direction (30 and 60 only need `00-org-baseline`; 40 needs `20-projects` for the plogs project; 50 only needs `00-org-baseline`).

Downstream (Tier 1 baselines + Tier 2 LZs) consumes Tier 0 via `terraform_remote_state`. Both wait for Tier 0 to be applied at least through `20-projects` (that's where `platform_project_ids` becomes available).

## What this repo does NOT do

- **Does not create the Organization itself** &mdash; it's a Google Workspace / Cloud Identity artefact. Stack `00-org-baseline` **anchors** to it (see the anchor + baseline pattern above).
- **Does not deploy VPCs, NAT, firewalls, or FortiGates** &mdash; that's Tier 2. The FortiGate perimeter appliance lives in `pnet-hub` (created by the LZ). See [ADR-0008](adr/0008-ingress-bypasses-perimeter-appliance.md) for the ingress-bypasses-perimeter design.
- **Does not deploy DNS zones, log dashboards, KMS keys, or SCC config** &mdash; that's Tier 1 (inside the platform projects this repo creates).
- **Does not configure Workforce Identity Federation** &mdash; that's Tier 1 identity-baseline. See [ADR-0004](adr/0004-no-workforce-identity-federation-here.md).
- **Does not manage the state bucket** &mdash; bootstrap is a one-time shell script.

## Failure modes and blast radius

- **`create` mode against pre-existing folders with the same display name** &mdash; `google_folder` errors on unique constraint at parent scope. Recovery: switch to `existing` mode, or delete the pre-existing folder (unlikely acceptable).
- **First apply of stack `40-org-logging` (v0.3.0)** &mdash; org-sink writer identity propagation lag can cause the follow-on `google_project_iam_member` binding to fail with "principal not found". Recovery: re-apply after 30 seconds; Terraform retries the binding cleanly.
- **`terraform destroy` on stack `20-projects`** &mdash; fails by design because every platform project inherits `deletion_policy = "PREVENT"`. To genuinely destroy, override the policy per project, apply, then destroy. Two-step protection is intentional.
- **Home folder key mismatch in `platform_project_home_folder`** &mdash; the project falls back to the Organization root (with a plan-time warning via precondition). Fix the mapping and re-apply; `google_project.folder_id` updates in place.
- **Org-policy enforcement (v0.3.0) breaking a live workload** &mdash; mitigated by `dry_run = true` default in the catalogue. A policy flipped to enforce that breaks workloads is a rollback: revert the specific `enable_X` switch, apply.

## Framework alignment and maturity

Every architectural decision in this repo is mapped to the reference frameworks the portfolio supports (NIS2, ISO 27001/27002, NIST CSF, NIST SP 800-53, CIS GCP Foundation Benchmark, Google Cloud Architecture Framework) in [`security/control-mapping.md`](security/control-mapping.md). Per-decision maturity paths (current implementation / enhanced / high-isolation option) in [`security/maturity.md`](security/maturity.md).

**Language convention**: framework references use "supports controls typically found in ..." rather than "complies with". Compliance depends on processes, evidence, people, and audit &mdash; not on a Terraform folder. See [`docs/adr/README.md`](adr/README.md#framework-language-convention).
