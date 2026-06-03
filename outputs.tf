# ── EKS ──────────────────────────────────────────────────────────────────────

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "kubeconfig_command" {
  description = "Run this to configure kubectl after apply"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ── ECR ───────────────────────────────────────────────────────────────────────

output "ecr_auth_service_url" {
  description = "ECR URL for auth-service image"
  value       = module.ecr.auth_service_url
}

output "ecr_account_service_url" {
  description = "ECR URL for account-service image"
  value       = module.ecr.account_service_url
}

output "ecr_transaction_service_url" {
  description = "ECR URL for transaction-service image"
  value       = module.ecr.transaction_service_url
}

output "ecr_notification_service_url" {
  description = "ECR URL for notification-service image"
  value       = module.ecr.notification_service_url
}

output "ecr_login_command" {
  description = "Docker login command for ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

# ── RDS ───────────────────────────────────────────────────────────────────────

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint — used by pods via AWS Secrets Manager"
  value       = module.rds.db_endpoint
  sensitive   = true
}

# ── ElastiCache ───────────────────────────────────────────────────────────────

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = module.elasticache.redis_endpoint
  sensitive   = true
}

# ── Platform URLs (available after helm module runs) ──────────────────────────

output "argocd_url" {
  description = "ArgoCD UI — port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443"
  value       = "https://localhost:8080 (via port-forward)"
}

output "grafana_url" {
  description = "Grafana UI — port-forward: kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80"
  value       = "http://localhost:3000 (via port-forward)"
}

output "rabbitmq_management_url" {
  description = "RabbitMQ management UI — port-forward: kubectl port-forward svc/rabbitmq -n finpay 15672:15672"
  value       = "http://localhost:15672 (via port-forward)"
}

output "next_steps" {
  description = "What to do after terraform apply"
  value       = <<-EOT
    1. Configure kubectl:
       aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}

    2. Verify nodes are ready:
       kubectl get nodes

    3. Check platform pods:
       kubectl get pods -n argocd
       kubectl get pods -n istio-system
       kubectl get pods -n monitoring
       kubectl get pods -n finpay

    4. Access ArgoCD UI:
       kubectl port-forward svc/argocd-server -n argocd 8080:443
       kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

    5. Access Grafana:
       kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80

    6. Teardown when done:
       bash scripts/destroy.sh
  EOT
}
