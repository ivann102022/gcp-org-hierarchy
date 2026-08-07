#!/usr/bin/env bash
###############################################################################
# File:        scripts/bootstrap-tfstate.sh
# Author:      Ismael Cruz
# Version:     0.1.0
# Description: One-time bootstrap of the Terraform state backend for
#              gcp-org-hierarchy and every downstream repo in the portfolio.
#              Creates a dedicated `ptfstate` project (if missing) and a
#              versioned GCS bucket (if missing) inside it, then grants the
#              executing identity roles/storage.admin on the bucket.
#
#              Idempotent: safe to re-run. Not part of any Terraform apply.
#
# Prereqs:
#   - gcloud CLI installed and authenticated with an account holding
#     roles/resourcemanager.organizationAdmin (or a scoped superset covering
#     project creation + storage.admin) and roles/billing.user on the
#     billing account.
#   - Environment overrides (or edit the defaults below):
#       ORG_ID              e.g. 123456789012
#       BILLING_ACCOUNT_ID  e.g. 01ABCD-234567-EFGH89
#       TFSTATE_PROJECT_ID  default: gcp0-prj-emp-ptfstate-01
#       TFSTATE_BUCKET      default: <owner>-tfstate-portfolio (set OWNER env)
#       TFSTATE_LOCATION    default: EU (multi-region)
#       PARENT_FOLDER_ID    optional (folder to nest ptfstate under)
###############################################################################

set -euo pipefail

# --- Configuration ----------------------------------------------------------
: "${ORG_ID:?ORG_ID is required (numeric organization ID)}"
: "${BILLING_ACCOUNT_ID:?BILLING_ACCOUNT_ID is required (billing account)}"
: "${OWNER:=REPLACE-ME}"

TFSTATE_PROJECT_ID="${TFSTATE_PROJECT_ID:-gcp0-prj-emp-ptfstate-01}"
TFSTATE_BUCKET="${TFSTATE_BUCKET:-${OWNER}-tfstate-portfolio}"
TFSTATE_LOCATION="${TFSTATE_LOCATION:-EU}"
PARENT_FOLDER_ID="${PARENT_FOLDER_ID:-}"

if [[ "${OWNER}" == "REPLACE-ME" && "${TFSTATE_BUCKET}" == "REPLACE-ME-tfstate-portfolio" ]]; then
  echo "ERROR: set OWNER=<your-portfolio-owner-slug> (or override TFSTATE_BUCKET explicitly)." >&2
  exit 1
fi

echo "==> Bootstrap Terraform state backend"
echo "    Org ID          : ${ORG_ID}"
echo "    Billing account : ${BILLING_ACCOUNT_ID}"
echo "    Project ID      : ${TFSTATE_PROJECT_ID}"
echo "    Bucket          : gs://${TFSTATE_BUCKET}"
echo "    Location        : ${TFSTATE_LOCATION}"
echo "    Parent folder   : ${PARENT_FOLDER_ID:-<none, project attaches to org root>}"
echo

# --- 1. Create (or verify) the tfstate project -----------------------------
if gcloud projects describe "${TFSTATE_PROJECT_ID}" >/dev/null 2>&1; then
  echo "==> Project ${TFSTATE_PROJECT_ID} already exists, skipping create"
else
  echo "==> Creating project ${TFSTATE_PROJECT_ID}"
  if [[ -n "${PARENT_FOLDER_ID}" ]]; then
    gcloud projects create "${TFSTATE_PROJECT_ID}" \
      --name="Terraform State (portfolio)" \
      --folder="${PARENT_FOLDER_ID}"
  else
    gcloud projects create "${TFSTATE_PROJECT_ID}" \
      --name="Terraform State (portfolio)" \
      --organization="${ORG_ID}"
  fi
fi

echo "==> Attaching billing account"
gcloud beta billing projects link "${TFSTATE_PROJECT_ID}" \
  --billing-account="${BILLING_ACCOUNT_ID}"

echo "==> Enabling storage.googleapis.com"
gcloud services enable storage.googleapis.com --project="${TFSTATE_PROJECT_ID}"

# --- 2. Create (or verify) the state bucket --------------------------------
if gcloud storage buckets describe "gs://${TFSTATE_BUCKET}" >/dev/null 2>&1; then
  echo "==> Bucket gs://${TFSTATE_BUCKET} already exists, skipping create"
else
  echo "==> Creating bucket gs://${TFSTATE_BUCKET}"
  gcloud storage buckets create "gs://${TFSTATE_BUCKET}" \
    --project="${TFSTATE_PROJECT_ID}" \
    --location="${TFSTATE_LOCATION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

echo "==> Enabling object versioning"
gcloud storage buckets update "gs://${TFSTATE_BUCKET}" --versioning

# --- 3. Grant executing identity storage.admin on the bucket ---------------
CALLER="$(gcloud config get-value account 2>/dev/null)"
echo "==> Granting roles/storage.admin on gs://${TFSTATE_BUCKET} to ${CALLER}"
gcloud storage buckets add-iam-policy-binding "gs://${TFSTATE_BUCKET}" \
  --member="user:${CALLER}" \
  --role="roles/storage.admin"

echo
echo "==> Bootstrap complete."
echo
echo "Next: edit each stack's backend.tf and set:"
echo "  bucket = \"${TFSTATE_BUCKET}\""
echo "or override at init time:"
echo "  terraform -chdir=stacks/00-org-baseline init -backend-config=\"bucket=${TFSTATE_BUCKET}\""
