#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# destroy.sh — Cleanly tears down the full EKS stack
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

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
ACCOUNT_ID="150103290775"

# ── Step 1 — Delete ArgoCD applications ──────────────────────────────────────
echo ""
echo "→ Step 1: Deleting ArgoCD applications..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" 2>/dev/null || true
kubectl delete --ignore-not-found -n argocd application --all 2>/dev/null || true
echo "  ✓ Done"

# ── Step 2 — Delete all ALBs ──────────────────────────────────────────────────
echo ""
echo "→ Step 2: Deleting ALBs..."
for arn in $(aws elbv2 describe-load-balancers \
  --region $REGION \
  --query "LoadBalancers[*].LoadBalancerArn" \
  --output text 2>/dev/null); do
  echo "  Deleting ALB $arn"
  aws elbv2 delete-load-balancer --load-balancer-arn $arn --region $REGION
done
echo "  Waiting 60s for ALBs to delete..."
sleep 60
echo "  ✓ Done"

# ── Step 3 — Delete NAT Gateways ─────────────────────────────────────────────
echo ""
echo "→ Step 3: Deleting NAT Gateways..."
for nat in $(aws ec2 describe-nat-gateways \
  --region $REGION \
  --filter "Name=state,Values=available" \
  --query "NatGateways[*].NatGatewayId" \
  --output text 2>/dev/null); do
  echo "  Deleting NAT $nat"
  aws ec2 delete-nat-gateway --nat-gateway-id $nat --region $REGION
done
echo "  Waiting 60s for NAT Gateways to delete..."
sleep 60
echo "  ✓ Done"

# ── Step 4 — Release Elastic IPs ─────────────────────────────────────────────
echo ""
echo "→ Step 4: Releasing Elastic IPs..."
for alloc in $(aws ec2 describe-addresses \
  --region $REGION \
  --query "Addresses[*].AllocationId" \
  --output text 2>/dev/null); do
  echo "  Releasing EIP $alloc"
  aws ec2 release-address --allocation-id $alloc --region $REGION 2>/dev/null || true
done
echo "  ✓ Done"

# ── Step 5 — Force delete ECR repos ──────────────────────────────────────────
echo ""
echo "→ Step 5: Force deleting ECR repositories..."
for repo in finpay-auth finpay-account finpay-transaction finpay-notification \
            finpay-api finpay-web finpay-rabbitmq; do
  # aws ecr delete-repository \
    --repository-name $repo \
    --force \
    --region $REGION 2>/dev/null && echo "  Deleted $repo" || true
done
echo "  ✓ Done"

# ── Step 6 — Terraform destroy ───────────────────────────────────────────────
echo ""
echo "→ Step 6: Running terraform destroy..."
terraform destroy -auto-approve

# ── Step 7 — Clean up any remaining VPC resources ────────────────────────────
echo ""
echo "→ Step 7: Cleaning up any remaining VPC resources..."

# Get VPC ID from state or by tag
VPC_ID=$(aws ec2 describe-vpcs \
  --region $REGION \
  --filters "Name=tag:Project,Values=finpay" \
  --query "Vpcs[0].VpcId" \
  --output text 2>/dev/null)

if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
  echo "  Found leftover VPC $VPC_ID — cleaning up..."

  # Delete security groups
  for sg in $(aws ec2 describe-security-groups \
    --region $REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" \
    --output text 2>/dev/null); do
    aws ec2 delete-security-group --group-id $sg --region $REGION 2>/dev/null || true
  done

  # Detach and delete IGW
  for igw in $(aws ec2 describe-internet-gateways \
    --region $REGION \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query "InternetGateways[*].InternetGatewayId" \
    --output text 2>/dev/null); do
    aws ec2 detach-internet-gateway \
      --internet-gateway-id $igw --vpc-id $VPC_ID --region $REGION 2>/dev/null || true
    aws ec2 delete-internet-gateway \
      --internet-gateway-id $igw --region $REGION 2>/dev/null || true
  done

  # Delete subnets
  for subnet in $(aws ec2 describe-subnets \
    --region $REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[*].SubnetId" \
    --output text 2>/dev/null); do
    aws ec2 delete-subnet --subnet-id $subnet --region $REGION 2>/dev/null || true
  done

  # Delete VPC
  aws ec2 delete-vpc --vpc-id $VPC_ID --region $REGION 2>/dev/null && \
    echo "  ✓ VPC deleted" || echo "  VPC already deleted"
else
  echo "  No leftover VPC found"
fi

echo ""
echo "─────────────────────────────────────────────"
echo " Destroy complete. All resources deleted."
echo " Your credit stops being consumed."
echo "─────────────────────────────────────────────"
