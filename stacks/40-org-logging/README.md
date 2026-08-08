<!--
File:        stacks/40-org-logging/README.md
Author:      Ismael Cruz
Version:     0.1.0
Description: Documentation for the org-logging stack — organization-level
             log sink routing every project's logs into plogs.
-->

# Stack `40-org-logging`

Provisions the **organization-level log sink** (`google_logging_organization_sink`) that captures logs from every project in every folder under the Organization and routes them to the `plogs` project (from Tier 0 `20-projects`). Also grants the sink's writer identity the IAM permission needed to write to the destination.

Full rationale for placing the sink in Tier 0 (rather than in `gcp-observability-baseline`) is in [ADR-0003](../../docs/adr/0003-org-sink-in-tier0-not-obs-baseline.md). Design choices for filter / destination / IAM binding ownership are in [ADR-0012](../../docs/adr/0012-org-sink-design.md).

## What it owns

- `google_logging_organization_sink.org` &mdash; the sink itself. `include_children = true` by default (captures every project in every folder). `unique_writer_identity = true` so GCP mints a dedicated writer SA per sink (audit clarity).
- `google_project_iam_member.writer_identity` &mdash; grants the sink's writer SA `roles/logging.bucketWriter` on the `plogs` project when `destination_type = "log_bucket"` and `create_writer_identity_binding = true` (default).

## What it does NOT do

- Does not create the destination log bucket &mdash; that's `gcp-observability-baseline/00-log-storage`. This stack routes to the destination but doesn't provision it.
- Does not create additional export destinations (BigQuery, Pub/Sub, GCS) &mdash; those live in `gcp-observability-baseline/10-log-exports` where the destinations are owned. The org sink at this level typically routes to the log bucket only; per-destination sinks in obs-baseline consume from there.
- Does not configure log-based metrics, alert policies, or dashboards &mdash; those live in `gcp-observability-baseline/20-monitoring-and-budgets`.

## Interlock with `gcp-observability-baseline`

Before this stack ships, `gcp-observability-baseline/00-log-storage` has a **deferred integration hook** (`var.org_sink_writer_identity`) that grants the writer SA `roles/logging.bucketWriter` on `plogs` &mdash; obs-baseline was designed to work standalone during the period when this stack didn't exist yet.

Once this stack ships (v0.4.0 of Tier 0), two options for the transition:

1. **Recommended**: keep `create_writer_identity_binding = true` here (default) and set `org_sink_writer_identity = ""` in obs-baseline's tfvars (disables the deferred hook). Single owner of the binding &mdash; this stack.
2. **Interim**: keep both stacks binding the SA. `google_project_iam_member` is idempotent at the API level; the effective IAM policy has one binding for the same (member, role) pair. Ugly (two Terraform states own the same effective binding) but functionally safe during the migration window.

## Inputs

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `org_baseline_state_bucket` | Yes | &mdash; | Remote state for `00-org-baseline`. |
| `org_projects_state_bucket` | Yes | &mdash; | Remote state for `20-projects` (provides `plogs`). |
| `enable_org_sink` | No | `false` | Master switch. |
| `create_writer_identity_binding` | No | `true` | Whether this stack owns the IAM binding on plogs. |
| `sink_name` | No | `"central"` | Short name segment for the sink resource. |
| `sink_filter` | No | `""` (all logs) | Cloud Logging filter. Common override: `severity>=WARNING` for cost. |
| `include_children` | No | `true` | Capture every project in every folder. Almost always true. |
| `disabled` | No | `false` | Pause/resume without deleting the sink. |
| `destination_type` | No | `"log_bucket"` | `log_bucket` / `bigquery` / `pubsub` / `storage`. |
| `destination_log_bucket` | Required if `log_bucket` | `"_Default"` | Bucket in plogs. Override to custom bucket from obs-baseline. |
| `destination_log_bucket_location` | No | `"global"` | Bucket location. |
| `destination_override` | Required for non-log_bucket | `""` | Full destination string for BQ/PubSub/GCS. |
| `exclusions` | No | `{}` | Sink-level exclusions (filter before export). |

Full spec in [`variables.tf`](variables.tf).

## Outputs

| Output | Type | Purpose |
|---|---|---|
| `log_sink_id` | `string` | Sink resource name. |
| `log_sink_name` | `string` | Bare sink name. |
| `log_sink_writer_identity` | `string` | `"serviceAccount:..."` &mdash; consumed by obs-baseline. |
| `log_sink_destination` | `string` | Full destination string. |
| `log_sink_include_children` | `bool` | Echo of the flag. |
| `log_sink_filter` | `string` | Echo of the filter. |

Full contract in [`../../docs/contract.md`](../../docs/contract.md).

## Required IAM

- `roles/logging.configWriter` at the Organization scope (to create org sinks).
- `roles/resourcemanager.projectIamAdmin` on `plogs` (when `create_writer_identity_binding = true`).

## Apply

```bash
terraform -chdir=stacks/40-org-logging init
terraform -chdir=stacks/40-org-logging plan
terraform -chdir=stacks/40-org-logging apply
```

## Failure modes

- **Writer identity propagation lag**: first apply of `google_project_iam_member` after the sink is created may fail with "principal not found" (~30s propagation). Re-apply resolves it. Terraform's dependency graph does not know about the async propagation.
- **Sink filter with typo**: `google_logging_organization_sink` accepts syntactically-valid filters that match nothing. No error at apply; logs simply do not export. Verify with `gcloud logging read '<filter>' --organization <org_id>` before applying.
- **`include_children = false` with the expectation of org-wide capture**: sink only captures Org-scope resources (rare; almost nothing logs at that scope). Symptom: destination bucket receives ~zero logs. Fix: flip to `true`.
- **Destination bucket doesn't exist**: apply of `google_logging_organization_sink` succeeds (GCP validates the destination format, not existence). Sink writes fail silently at runtime. Fix: create the bucket via `gcp-observability-baseline/00-log-storage` first.
- **`terraform destroy`**: removes the sink; org-wide log export stops immediately. Coordinate with security / SOC team before destroying &mdash; this is a live audit dependency.
