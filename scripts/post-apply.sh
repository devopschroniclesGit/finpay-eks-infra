#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# post-apply.sh — Run after terraform apply
# Installs RabbitMQ and Prometheus which are managed outside Terraform
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

ACCOUNT_ID="150103290775"
REGION="us-east-1"
CLUSTER_NAME="finpay-eks"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-changeme}"

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

# ── Step 3 — Install EBS CSI addon ───────────────────────────────────────────
echo ""
echo "→ Step 3: Installing EBS CSI addon..."
aws eks create-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name aws-ebs-csi-driver \
  --region "$REGION" 2>/dev/null || echo "  EBS CSI addon already exists"

echo "  Waiting for EBS CSI to become ACTIVE..."
while true; do
  STATUS=$(aws eks describe-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name aws-ebs-csi-driver \
    --region "$REGION" \
    --query addon.status --output text)
  echo "  Status: $STATUS"
  [ "$STATUS" = "ACTIVE" ] && break
  sleep 10
done
echo "  ✓ EBS CSI addon active"

# ── Step 4 — Label finpay namespace for Istio ─────────────────────────────────
echo ""
echo "→ Step 4: Labelling finpay namespace for Istio injection..."
kubectl create namespace finpay 2>/dev/null || true
kubectl label namespace finpay istio-injection=enabled --overwrite
echo "  ✓ Istio injection enabled on finpay namespace"

# ── Step 5 — Deploy RabbitMQ ──────────────────────────────────────────────────
echo ""
echo "→ Step 5: Deploying RabbitMQ..."
kubectl delete statefulset rabbitmq -n finpay 2>/dev/null || true
kubectl delete svc rabbitmq -n finpay 2>/dev/null || true
sleep 10
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

# ── Step 6 — Install Prometheus + Grafana ─────────────────────────────────────
echo ""
echo "→ Step 6: Installing Prometheus + Grafana..."
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

# ── Step 7 — Apply ClusterSecretStore ─────────────────────────────────────────
echo ""
echo "→ Step 7: Applying ClusterSecretStore..."
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

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────"
echo " Post-apply complete. Cluster is ready."
echo ""
echo " Access ArgoCD:"
echo "   kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0 8080:80"
echo "   Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo " Access Grafana:"
echo "   kubectl port-forward svc/monitoring-grafana -n monitoring --address 0.0.0.0 3000:80"
echo "   Login: admin / $GRAFANA_PASSWORD"
echo ""
echo " Access RabbitMQ:"
echo "   kubectl port-forward svc/rabbitmq -n finpay --address 0.0.0.0 15672:15672"
echo "   Login: finpay / FinPay@RMQ2024!"
echo "─────────────────────────────────────────────"

# ── Step 8 — Print access URLs ────────────────────────────────────────────────
echo ""
echo "→ Step 8: Applying platform ingresses..."
kubectl apply -f ~/finpay-gitops/infrastructure/argocd/argocd-ingress.yaml 2>/dev/null || true
kubectl apply -f ~/finpay-gitops/infrastructure/monitoring/grafana-ingress.yaml 2>/dev/null || true

echo ""
echo "Waiting for ALBs to provision (60s)..."
sleep 60

echo ""
echo "─────────────────────────────────────────────"
echo " Platform URLs"
echo "─────────────────────────────────────────────"
echo " ArgoCD  : http://$(kubectl get ingress argocd-ingress -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)"
echo " Grafana : http://$(kubectl get ingress grafana-ingress -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)"
echo " API     : http://$(kubectl get ingress finpay-api -n finpay -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)"
echo "─────────────────────────────────────────────"
