<!--
File:        stacks/00-org-baseline/README.md
Author:      Ismael Cruz
Version:     0.2.0
Description: Documentation for the org-baseline stack — the anchor + baseline
             of Tier 0. Anchors the portfolio to the pre-existing GCP
             Organization by publishing contract facts (organization_id,
             organization_domain, billing_account_id) and administers the
             minimum org-scope elements that do not belong to any specific
             discipline (essential contacts).
-->

# Stack `00-org-baseline`

The **anchor + baseline** of Tier 0. Encodes two active responsibilities:

1. **Anchor** &mdash; publish `organization_id`, `organization_name`, `organization_domain`, and `billing_account_id` as **contractual facts** for every downstream stack and repo. Downstream never re-discovers the Org; they read this contract via `terraform_remote_state`.

2. **Baseline** &mdash; provision the minimum org-scope elements administered from apply #1 that do not belong to any specific discipline. Today: `google_essential_contacts_contact` at Org scope.

Same conceptual role as the AWS sibling `aws-org-hierarchy/00-org-baseline`. In AWS the anchor is a `create` (Organization does not exist); in GCP the anchor is a `data` (Organization pre-exists). Different implementation, identical responsibility.

## Content rule (guardrail for future additions)

This stack is intentionally minimal. To keep it from becoming a catch-all that erodes the reason `30-org-policies` / `40-org-logging` / `50-org-iam` / `60-tags` exist, a candidate belongs here **only if all three criteria hold**:

1. **Org-scope** &mdash; its natural scope is the Organization, not a folder or project.
2. **Fundacional** &mdash; established at apply #1, not at apply #N.
3. **Not a discipline** &mdash; does not fall cleanly under Policies (30), Logging (40), IAM (50), or Tags (60), *even if org-scope*.

Worked examples in [ADR-0007](../../docs/adr/0007-content-rule-for-org-baseline.md).

Essential contacts pass all three (org-scope + fundacional + not-a-discipline). Org-scope IAM bindings (Org Admin, Project Creator) would fail criterion 3 &mdash; they belong in `50-org-iam` even though they're org-scope and fundacional.

## What it owns

- `data "google_organization" "this"` &mdash; looked up by `var.organization_domain`. **Always a data source**: GCP does not allow Terraform to create Organizations (they arrive with your Google Workspace / Cloud Identity tenant). See [ADR-0001](../../docs/adr/0001-two-modes-only-existing-and-create.md).
- `google_essential_contacts_contact` per entry in `var.essential_contacts` &mdash; only when `var.enable_essential_contacts = true`. Meets the content rule above.

## What it does NOT do

- Does not create the Organization &mdash; impossible in Terraform.
- Does not create folders or projects &mdash; those are stacks `10` and `20`.
- Does not manage org-scope IAM bindings (Org Admin, etc.) &mdash; that's stack `50` (planned v0.4.0). Fails criterion 3 of the content rule (IAM is a discipline).
- Does not deploy the org log sink &mdash; that's stack `40` (planned v0.3.0). Fails criterion 3 (Logging is a discipline). See [ADR-0003](../../docs/adr/0003-org-sink-in-tier0-not-obs-baseline.md).
- Does not manage org policies &mdash; that's stack `30` (planned v0.3.0). Fails criterion 3.
- Does not manage tags &mdash; that's stack `60` (planned v0.4.0). Fails criterion 3.

## Inputs

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `organization_domain` | Yes | &mdash; | Primary domain of the Org (e.g. `"example.com"`). |
| `billing_account_id` | Yes | &mdash; | Format `XXXXXX-XXXXXX-XXXXXX`. Passed through to `20-projects` and exposed via contract. |
| `organization_mode` | No | `"existing"` | Reserved for future modes; only `existing` / `create` valid. See [ADR-0001](../../docs/adr/0001-two-modes-only-existing-and-create.md). |
| `enable_essential_contacts` | No | `false` | Master switch for essential contacts. |
| `essential_contacts` | No | `{}` | Map of email &rarr; list of notification categories. |
| `essential_contact_language` | No | `"en"` | BCP-47 language tag for notifications. |

Full inputs in [`variables.tf`](variables.tf).

## Outputs

| Output | Type | Downstream consumer |
|---|---|---|
| `organization_id` | `string` | Every downstream stack + repo. Contract fact. |
| `organization_domain` | `string` | Downstream repos that need to construct URIs / IAM member strings referencing the domain. |
| `organization_name` | `string` | Downstream stacks that call APIs requiring the qualified `organizations/<id>` form. |
| `billing_account_id` | `string` | `20-projects` (this repo) + any downstream repo linking additional projects. Contract fact. |
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
