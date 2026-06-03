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

resource "helm_release" "rabbitmq" {
  name       = "rabbitmq"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "rabbitmq"
  namespace  = "finpay"
  create_namespace = true
  version    = "12.6.0"

  values = [<<-YAML
    auth:
      username: finpay
      password: "${var.rabbitmq_password}"
      erlangCookie: "finpay-erlang-cookie-change-me"

    persistence:
      enabled: true
      size: 8Gi
      storageClass: gp2

    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 1000m
        memory: 512Mi

    # Pre-create finpay vhost and exchanges via plugins
    extraConfiguration: |
      default_vhost = finpay
      default_permissions.configure = .*
      default_permissions.read = .*
      default_permissions.write = .*

    plugins: "rabbitmq_management rabbitmq_peer_discovery_k8s"

    service:
      type: ClusterIP
      amqpPort: 5672
      managerPort: 15672

    metrics:
      enabled: true
      serviceMonitor:
        enabled: true
  YAML
  ]

  depends_on = [helm_release.istiod]
}

# ── 6. Prometheus + Grafana (kube-prometheus-stack) ───────────────────────────

resource "helm_release" "prometheus_stack" {
  name       = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "monitoring"
  create_namespace = true
  version    = "57.0.1"

  timeout = 600   # Stack takes ~5 minutes to come up

  values = [<<-YAML
    grafana:
      enabled: true
      adminPassword: "${var.grafana_admin_password}"
      persistence:
        enabled: true
        size: 5Gi
        storageClassName: gp2
      sidecar:
        dashboards:
          enabled: true
          label: grafana_dashboard
      additionalDataSources:
        - name: Loki
          type: loki
          url: http://loki:3100
          access: proxy
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 256Mi

    prometheus:
      prometheusSpec:
        retention: 15d
        storageSpec:
          volumeClaimTemplate:
            spec:
              storageClassName: gp2
              resources:
                requests:
                  storage: 20Gi
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        # Scrape finpay pods with prometheus annotations
        additionalScrapeConfigs:
          - job_name: finpay-services
            kubernetes_sd_configs:
              - role: pod
                namespaces:
                  names: [finpay]
            relabel_configs:
              - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                action: keep
                regex: "true"
              - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
                action: replace
                target_label: __metrics_path__
                regex: (.+)
              - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
                action: replace
                regex: ([^:]+)(?::\d+)?;(\d+)
                replacement: $1:$2
                target_label: __address__
              - source_labels: [__meta_kubernetes_pod_label_app]
                target_label: service
          - job_name: rabbitmq
            static_configs:
              - targets: ["rabbitmq.finpay.svc.cluster.local:15692"]

    alertmanager:
      alertmanagerSpec:
        resources:
          requests:
            cpu: 50m
            memory: 64Mi

    nodeExporter:
      enabled: true

    kubeStateMetrics:
      enabled: true
  YAML
  ]

  depends_on = [helm_release.istiod]
}

# ── 7. Kiali (Istio service mesh UI) ─────────────────────────────────────────

resource "helm_release" "kiali" {
  name       = "kiali-server"
  repository = "https://kiali.org/helm-charts"
  chart      = "kiali-server"
  namespace  = "istio-system"
  create_namespace = true
  version    = "1.80.0"

  values = [<<-YAML
    auth:
      strategy: anonymous   # Fine for demo — lock down for prod
    external_services:
      prometheus:
        url: http://monitoring-prometheus.monitoring:9090
      grafana:
        enabled: true
        url: http://monitoring-grafana.monitoring:80
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
  YAML
  ]

  depends_on = [helm_release.prometheus_stack, helm_release.istiod]
}
