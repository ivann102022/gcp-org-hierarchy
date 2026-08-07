<!--
File:        stacks/00-org-baseline/README.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Documentation for the org-baseline stack — the anchor of
             Tier 0. References the GCP Organization by domain and
             optionally provisions essential contacts.
-->

# Stack `00-org-baseline`

The **anchor** stack of Tier 0. Locates the GCP Organization by primary domain, exposes the canonical `organization_id` for every downstream stack and every downstream repo, and optionally provisions essential contacts at the Organization scope.

## What it owns

- `data "google_organization" "this"` &mdash; looked up by `var.organization_domain`. **Always a data source**: GCP does not allow Terraform to create Organizations (they arrive with your Google Workspace / Cloud Identity tenant). See [ADR-0001](../../docs/adr/0001-two-modes-only-existing-and-create.md).
- `google_essential_contacts_contact` per entry in `var.essential_contacts` &mdash; only when `var.enable_essential_contacts = true`.

## What it does NOT do

- Does not create the Organization &mdash; impossible in Terraform.
- Does not create folders or projects &mdash; those are stacks `10` and `20`.
- Does not manage org-scope IAM &mdash; that's stack `50` (planned v0.3.0).
- Does not deploy the org log sink &mdash; that's stack `40` (planned v0.2.0). See [ADR-0003](../../docs/adr/0003-org-sink-in-tier0-not-obs-baseline.md).

## Inputs

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `organization_domain` | Yes | &mdash; | Primary domain of the Org (e.g. `"example.com"`). |
| `billing_account_id` | Yes | &mdash; | Format `XXXXXX-XXXXXX-XXXXXX`. Passed through to `20-projects` and exposed via contract. |
| `organization_mode` | No | `"existing"` | Reserved for future modes; only `existing` / `create` valid in v0.1.0. |
| `enable_essential_contacts` | No | `false` | Master switch for essential contacts. |
| `essential_contacts` | No | `{}` | Map of email &rarr; list of notification categories. |
| `essential_contact_language` | No | `"en"` | BCP-47 language tag for notifications. |

Full inputs in [`variables.tf`](variables.tf).

## Outputs

| Output | Type | Downstream consumer |
|---|---|---|
| `organization_id` | `string` | Every downstream stack + repo. |
| `organization_domain` | `string` | Downstream repos that need to construct URIs / IAM member strings referencing the domain. |
| `organization_name` | `string` | Downstream stacks that call APIs requiring the qualified `organizations/<id>` form. |
| `billing_account_id` | `string` | `20-projects` (this repo) + any downstream repo linking additional projects. |
| `mode` | `string` | Downstream `precondition` blocks. |
| `essential_contact_emails` | `list(string)` | Audit tooling that checks contact coverage. |

Full contract in [`../../docs/contract.md`](../../docs/contract.md).

## Required IAM

The executing identity needs:

- `roles/resourcemanager.organizationViewer` at the Organization scope (always).
- `roles/essentialcontacts.admin` at the Organization scope (only when `enable_essential_contacts = true`).

## Apply

```bash
terraform -chdir=stacks/00-org-baseline init
terraform -chdir=stacks/00-org-baseline plan
terraform -chdir=stacks/00-org-baseline apply
```

Backend bucket must be created first via [`../../scripts/bootstrap-tfstate.sh`](../../scripts/bootstrap-tfstate.sh) and either edited into [`backend.tf`](backend.tf) or passed via `-backend-config="bucket=<name>"` at init time.

## Failure modes

- **Domain not found**: `data "google_organization"` returns a "not found" error. Verify `organization_domain` matches the Workspace / Cloud Identity primary domain exactly (lowercase; no trailing dot).
- **Insufficient IAM**: `data "google_organization"` needs at least `roles/resourcemanager.organizationViewer`. Errors surface as 403 with a clear message.
- **Essential contact email domain mismatch**: some organisations restrict essential contacts to domains associated with the Workspace tenant. Google returns a validation error at apply time.
