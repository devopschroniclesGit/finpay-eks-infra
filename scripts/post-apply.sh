#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# post-apply.sh — Run after terraform apply
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

ACCOUNT_ID="150103290775"
REGION="us-east-1"
CLUSTER_NAME="finpay-eks"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-changeme}"
API_ALB_URL=""

echo "─────────────────────────────────────────────"
echo " FinPay Post-Apply Bootstrap"
echo "─────────────────────────────────────────────"

# ── Step 1 — Sync clock ───────────────────────────────────────────────────────
echo ""
echo "→ Step 1: Syncing clock..."
sudo chronyc makestep
echo "  ✓ Clock synced: $(date)"

# ── Step 2 — Configure kubectl ────────────────────────────────────────────────
echo ""
echo "→ Step 2: Configuring kubectl..."
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"
echo "  ✓ kubectl configured"

# ── Step 3 — Attach EBS CSI policy to node role ───────────────────────────────
echo ""
echo "→ Step 3: Attaching EBS CSI policy to node role..."
aws iam attach-role-policy \
  --role-name finpay-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  2>/dev/null || echo "  Policy already attached"

# Install EBS CSI addon
aws eks create-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name aws-ebs-csi-driver \
  --region "$REGION" 2>/dev/null || echo "  EBS CSI addon already exists"

echo "  Waiting for EBS CSI to become ACTIVE..."
for i in $(seq 1 30); do
  STATUS=$(aws eks describe-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name aws-ebs-csi-driver \
    --region "$REGION" \
    --query addon.status --output text 2>/dev/null)
  echo "  Status: $STATUS"
  [ "$STATUS" = "ACTIVE" ] && break
  sleep 10
done
echo "  ✓ EBS CSI addon active"

# ── Step 4 — Add security group rules for RDS and Redis ──────────────────────
echo ""
echo "→ Step 4: Adding security group rules..."
EKS_SG=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
  --output text 2>/dev/null)

RDS_SG=$(aws rds describe-db-instances \
  --db-instance-identifier finpay-postgres \
  --region "$REGION" \
  --query "DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId" \
  --output text 2>/dev/null)

REDIS_SG=$(aws elasticache describe-cache-clusters \
  --region "$REGION" \
  --query "CacheClusters[?contains(CacheClusterId,'finpay')].SecurityGroups[0].SecurityGroupId" \
  --output text 2>/dev/null)

if [ -n "$EKS_SG" ] && [ -n "$RDS_SG" ]; then
  aws ec2 authorize-security-group-ingress \
    --group-id "$RDS_SG" --protocol tcp --port 5432 \
    --source-group "$EKS_SG" --region "$REGION" 2>/dev/null || true
  echo "  ✓ RDS rule added"
fi

if [ -n "$EKS_SG" ] && [ -n "$REDIS_SG" ]; then
  aws ec2 authorize-security-group-ingress \
    --group-id "$REDIS_SG" --protocol tcp --port 6379 \
    --source-group "$EKS_SG" --region "$REGION" 2>/dev/null || true
  echo "  ✓ Redis rule added"
fi

# ── Step 5 — Label finpay namespace for Istio ────────────────────────────────
echo ""
echo "→ Step 5: Labelling finpay namespace for Istio injection..."
kubectl create namespace finpay 2>/dev/null || true
kubectl label namespace finpay istio-injection=enabled --overwrite
echo "  ✓ Istio injection enabled"

# ── Step 6 — Deploy RabbitMQ ─────────────────────────────────────────────────
echo ""
echo "→ Step 6: Deploying RabbitMQ..."
kubectl delete statefulset rabbitmq -n finpay 2>/dev/null || true
kubectl delete svc rabbitmq -n finpay 2>/dev/null || true
kubectl delete pvc data-rabbitmq-0 -n finpay 2>/dev/null || true
sleep 15

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: rabbitmq
  namespace: finpay
spec:
  serviceName: rabbitmq
  replicas: 1
  selector:
    matchLabels:
      app: rabbitmq
  template:
    metadata:
      labels:
        app: rabbitmq
    spec:
      containers:
        - name: rabbitmq
          image: ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/finpay-rabbitmq:3.13-management
          ports:
            - containerPort: 5672
              name: amqp
            - containerPort: 15672
              name: management
          env:
            - name: RABBITMQ_DEFAULT_USER
              value: finpay
            - name: RABBITMQ_DEFAULT_PASS
              value: "FinPay@RMQ2024!"
            - name: RABBITMQ_DEFAULT_VHOST
              value: finpay
          volumeMounts:
            - name: data
              mountPath: /var/lib/rabbitmq
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 512Mi
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp2
        resources:
          requests:
            storage: 8Gi
---
apiVersion: v1
kind: Service
metadata:
  name: rabbitmq
  namespace: finpay
spec:
  selector:
    app: rabbitmq
  ports:
    - name: amqp
      port: 5672
    - name: management
      port: 15672
  type: ClusterIP
YAML
echo "  ✓ RabbitMQ deployed"

# ── Step 7 — Install Prometheus + Grafana ────────────────────────────────────
echo ""
echo "→ Step 7: Installing Prometheus + Grafana..."
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

helm upgrade --install monitoring \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword="$GRAFANA_PASSWORD" \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=gp2 \
  --set grafana.persistence.storageClassName=gp2 \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=5Gi \
  --timeout 15m \
  --wait
echo "  ✓ Prometheus + Grafana installed"

# ── Step 8 — Apply ClusterSecretStore ────────────────────────────────────────
echo ""
echo "→ Step 8: Applying ClusterSecretStore..."
kubectl apply -f - <<YAML
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${REGION}
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
YAML
echo "  ✓ ClusterSecretStore applied"

# ── Step 9 — Apply ArgoCD applications ───────────────────────────────────────
echo ""
echo "→ Step 9: Applying ArgoCD applications..."
kubectl apply -f - <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: finpay-prod
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/devopschroniclesGit/finpay-gitops
    targetRevision: main
    path: apps/finpay-api/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: finpay
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML

kubectl apply -f - <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: finpay-web
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/devopschroniclesGit/finpay-gitops
    targetRevision: main
    path: apps/finpay-web/base
  destination:
    server: https://kubernetes.default.svc
    namespace: finpay
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML
echo "  ✓ ArgoCD applications applied"

# ── Step 10 — Apply ingresses ────────────────────────────────────────────────
echo ""
echo "→ Step 10: Applying platform ingresses..."
kubectl apply -f ~/finpay-gitops/infrastructure/argocd/argocd-ingress.yaml 2>/dev/null || true
kubectl apply -f ~/finpay-gitops/infrastructure/monitoring/grafana-ingress.yaml 2>/dev/null || true
echo "  ✓ Ingresses applied"

# ── Step 11 — Seed database ──────────────────────────────────────────────────
echo ""
echo "→ Step 11: Seeding database (waiting for pods to be ready)..."
echo "  Waiting 120s for pods to start..."
sleep 120

API_POD=$(kubectl get pods -n finpay -l app.kubernetes.io/name=auth-service \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -n "$API_POD" ]; then
  kubectl exec -n finpay "$API_POD" -c auth-service -- node -e "
const{PrismaClient}=require('@prisma/client');
const bcrypt=require('bcryptjs');
const prisma=new PrismaClient();
async function main(){
  const hash=await bcrypt.hash('password123',10);
  await prisma.user.upsert({where:{email:'alice@finpay.dev'},update:{},create:{email:'alice@finpay.dev',password:hash,name:'Alice Demo',account:{create:{balance:1000000}}}});
  await prisma.user.upsert({where:{email:'bob@finpay.dev'},update:{},create:{email:'bob@finpay.dev',password:hash,name:'Bob Demo',account:{create:{balance:500000}}}});
  console.log('Seeded');
  await prisma.\$disconnect();
}
main().catch(e=>{console.error(e);process.exit(1);});
" && echo "  ✓ Database seeded" || echo "  ⚠ Seed failed — run manually later"
else
  echo "  ⚠ Auth pod not ready — seed manually after pods start"
fi

# ── Step 12 — Update finpay-web with new API URL ─────────────────────────────
echo ""
echo "→ Step 12: Updating finpay-web with new API URL..."
echo "  Waiting 60s for ALBs to provision..."
sleep 60

API_ALB=$(kubectl get ingress finpay-ingress -n finpay \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)

if [ -n "$API_ALB" ]; then
  cd ~/finpay-web
  echo "VITE_API_URL=http://${API_ALB}/api/v1" > .env.production
  npm run build

  aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin \
    "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

  docker build --no-cache \
    -t "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/finpay-web:latest" .
  docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/finpay-web:latest"
  kubectl rollout restart deployment finpay-web -n finpay
  echo "  ✓ finpay-web updated with API URL: http://${API_ALB}/api/v1"
  cd ~/finpay-eks-infra
else
  echo "  ⚠ Could not get API ALB URL — update finpay-web manually"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────"
echo " Platform URLs"
echo "─────────────────────────────────────────────"
echo " API     : http://$(kubectl get ingress finpay-ingress -n finpay -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)"
echo " Web UI  : http://$(kubectl get ingress finpay-web -n finpay -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)"
echo " ArgoCD  : http://$(kubectl get ingress argocd-ingress -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)"
echo " Grafana : http://$(kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)"
echo ""
echo " Demo accounts:"
echo "   alice@finpay.dev / password123  (ZAR 10,000)"
echo "   bob@finpay.dev   / password123  (ZAR 5,000)"
echo "   Bob account ID: f267bce9-9464-4783-b294-b5827cba2293"
echo ""
echo " ArgoCD password:"
echo "   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "─────────────────────────────────────────────"
