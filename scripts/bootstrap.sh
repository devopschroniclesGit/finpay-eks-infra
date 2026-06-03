#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# bootstrap.sh — Run ONCE before terraform init
# Creates the S3 bucket + DynamoDB table for remote Terraform state
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REGION="us-east-1"
BUCKET="finpay-eks-terraform-state"
TABLE="finpay-eks-terraform-locks"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "─────────────────────────────────────────────"
echo " FinPay EKS — Terraform Bootstrap"
echo " Account : $ACCOUNT_ID"
echo " Region  : $REGION"
echo " Bucket  : $BUCKET"
echo " Table   : $TABLE"
echo "─────────────────────────────────────────────"

# ── S3 Bucket ─────────────────────────────────────────────────────────────────

echo ""
echo "→ Creating S3 bucket for Terraform state..."

aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" 2>/dev/null || echo "  Bucket already exists — skipping"

# Enable versioning so we can recover previous states
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

# ── DynamoDB Table (state locking) ────────────────────────────────────────────

echo ""
echo "→ Creating DynamoDB table for state locking..."

aws dynamodb create-table \
  --table-name "$TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" 2>/dev/null || echo "  Table already exists — skipping"

echo "  ✓ DynamoDB table ready: $TABLE"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "─────────────────────────────────────────────"
echo " Bootstrap complete. Now run:"
echo ""
echo "   cp terraform.tfvars.example terraform.tfvars"
echo "   # fill in real values in terraform.tfvars"
echo "   terraform init"
echo "   terraform plan"
echo "   terraform apply"
echo "─────────────────────────────────────────────"
