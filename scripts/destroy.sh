#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# destroy.sh — Cleanly tears down the full EKS stack
# Destroys in the right order to avoid dependency errors
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

echo "─────────────────────────────────────────────"
echo " FinPay EKS — Destroy"
echo " This will DELETE all AWS resources."
echo "─────────────────────────────────────────────"
read -rp " Type 'destroy' to confirm: " CONFIRM
if [[ "$CONFIRM" != "destroy" ]]; then
  echo "Aborted."
  exit 1
fi

CLUSTER_NAME="finpay-eks"
REGION="us-east-1"

echo ""
echo "→ Step 1: Remove Helm releases (avoids ALB/SG delete-order errors)..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" 2>/dev/null || true

kubectl delete --ignore-not-found \
  -n argocd application --all 2>/dev/null || true

# Destroy helm module first so ALB gets cleaned before SGs
terraform destroy \
  -target=module.helm \
  -auto-approve

echo ""
echo "→ Step 2: Destroy remaining resources..."
terraform destroy -auto-approve

echo ""
echo "─────────────────────────────────────────────"
echo " Destroy complete. All resources deleted."
echo " Your \$200 credit stops being consumed."
echo "─────────────────────────────────────────────"
