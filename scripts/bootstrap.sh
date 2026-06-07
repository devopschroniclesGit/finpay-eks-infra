#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# bootstrap.sh — Run ONCE before terraform init
# Creates the S3 bucket for remote Terraform state
# Note: DynamoDB locking removed — we use use_lockfile = true (S3 native locking)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REGION="us-east-1"
BUCKET="finpay-eks-terraform-state"

# ── Sync clock first (prevents AWS signature errors) ─────────────────────────
echo "→ Syncing clock..."
sudo chronyc makestep
echo "  ✓ Clock synced: $(date)"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo ""
echo "─────────────────────────────────────────────"
echo " FinPay EKS — Terraform Bootstrap"
echo " Account : $ACCOUNT_ID"
echo " Region  : $REGION"
echo " Bucket  : $BUCKET"
echo "─────────────────────────────────────────────"

# ── S3 Bucket ─────────────────────────────────────────────────────────────────
echo ""
echo "→ Creating S3 bucket for Terraform state..."

aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" 2>/dev/null || echo "  Bucket already exists — skipping"

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

# Enable server-side encryption
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block all public access
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "  ✓ S3 bucket ready: s3://$BUCKET"

# ── Verify AWS credentials work ───────────────────────────────────────────────
echo ""
echo "→ Verifying AWS credentials..."
aws sts get-caller-identity --output table
echo "  ✓ Credentials valid"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────"
echo " Bootstrap complete. Now run:"
echo ""
echo "   cp terraform.tfvars.example terraform.tfvars"
echo "   # fill in real values in terraform.tfvars"
echo "   terraform init"
echo "   terraform plan"
echo "   terraform apply --auto-approve"
echo "   GRAFANA_PASSWORD=FinPay@Graf2024! bash scripts/post-apply.sh"
echo "─────────────────────────────────────────────"
