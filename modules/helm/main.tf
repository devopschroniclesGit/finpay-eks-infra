# ── Namespaces — created via kubectl after cluster is ready ───────────────────
# Namespaces are created by ArgoCD on first sync from finpay-gitops
# The helm releases below specify createNamespace=true where needed

# ── 1. AWS Load Balancer Controller ──────────────────────────────────────────

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.1"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.alb_controller_role_arn
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  depends_on = [helm_release.alb_controller]
}

# ── 2. Istio ─────────────────────────────────────────────────────────────────

resource "helm_release" "istio_base" {
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  namespace  = "istio-system"
  create_namespace = true
  version    = "1.20.0"

  depends_on = [helm_release.alb_controller]
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = "istio-system"
  create_namespace = true
  version    = "1.20.0"

  set {
    name  = "pilot.resources.requests.cpu"
    value = "200m"
  }
  set {
    name  = "pilot.resources.requests.memory"
    value = "256Mi"
  }
  set {
    name  = "pilot.resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "pilot.resources.limits.memory"
    value = "512Mi"
  }

  depends_on = [helm_release.istio_base]
}

resource "helm_release" "istio_ingress" {
  name       = "istio-ingress"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = "istio-ingress"
  create_namespace = true
  version    = "1.20.0"

  depends_on = [helm_release.istiod]
}

# Istio sidecar injection label applied via kubectl after cluster is ready
# See post-apply instructions in outputs.tf
# kubectl label namespace finpay istio-injection=enabled

# ── 3. ArgoCD ─────────────────────────────────────────────────────────────────

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = "argocd"
  create_namespace = true
  version    = "6.7.0"

  values = [<<-YAML
    server:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 256Mi
    repoServer:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
    applicationSet:
      enabled: true
    notifications:
      enabled: true
    configs:
      params:
        server.insecure: true   # ALB terminates TLS
  YAML
  ]

  depends_on = [helm_release.alb_controller]
}

# ── 4. External Secrets Operator ─────────────────────────────────────────────

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = "external-secrets"
  create_namespace = true
  version    = "0.9.13"

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.eso_role_arn
  }

  depends_on = [helm_release.alb_controller]
}

# ClusterSecretStore is applied via ArgoCD (finpay-gitops/k8s/base/secrets.yaml)
# Cannot be applied here — kubernetes_manifest requires a live cluster during plan
# After terraform apply, ArgoCD will sync this resource automatically

# ── 5. RabbitMQ ───────────────────────────────────────────────────────────────


