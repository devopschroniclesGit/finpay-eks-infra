# finpay-eks-infra

Terraform infrastructure for FinPay microservices on AWS EKS.
Evolved from `finpay-infrastructure` (Elastic Beanstalk) → full Kubernetes stack.

## What this provisions

| Resource | Type | Description |
|---|---|---|
| VPC | Custom 10.0.0.0/16 | 3 public + 3 private + 3 data subnets across 3 AZs |
| EKS | 1.29 — t3.xlarge ×3 | Kubernetes cluster with managed node group |
| RDS | db.t3.medium PostgreSQL 15 | Private data subnet, gp3, encrypted, Performance Insights |
| ElastiCache | cache.t3.micro Redis 7 | Rate limiting + balance caching |
| ECR | 4 repositories | auth, account, transaction, notification — scan on push |
| AWS Secrets Manager | finpay/production | All app secrets — pulled by ESO into K8s |
| IRSA | 3 roles | ALB controller, ExternalDNS, External Secrets Operator |
| ALB Controller | Helm | AWS Load Balancer Controller for Ingress |
| Istio | 1.20 | Service mesh — mTLS, traffic management, Kiali UI |
| ArgoCD | 6.7 | GitOps — watches finpay-gitops repo, syncs to cluster |
| RabbitMQ | Bitnami 12.6 | AMQP message broker — finpay.transactions exchange |
| Prometheus + Grafana | kube-prometheus-stack 57 | Full observability stack |
| Kiali | 1.80 | Istio service mesh visualisation |

## Prerequisites

- AWS CLI configured: `aws configure`
- Terraform >= 1.5.0: `terraform --version`
- kubectl installed
- helm installed (optional — Terraform manages Helm)

## Deploy

```bash
# 1. Clone and enter repo
git clone https://github.com/your-org/finpay-eks-infra
cd finpay-eks-infra

# 2. Bootstrap remote state (run once)
bash scripts/bootstrap.sh

# 3. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in all values

# 4. Initialise
terraform init

# 5. Preview
terraform plan

# 6. Deploy (~20-25 minutes)
terraform apply
```

## After apply

Terraform prints next steps including:

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name finpay-eks

# Verify nodes
kubectl get nodes

# Access ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access Grafana
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80

# Access RabbitMQ Management UI
kubectl port-forward svc/rabbitmq -n finpay 15672:15672

# Access Kiali (Istio mesh UI)
kubectl port-forward svc/kiali -n istio-system 20001:20001
```

## Teardown

```bash
bash scripts/destroy.sh
```

Deletes everything. Stops all costs.

## File structure

```
finpay-eks-infra/
├── main.tf                      # Root — providers, backend, module calls
├── variables.tf                 # All input variables
├── outputs.tf                   # Cluster endpoint, ECR URLs, next steps
├── terraform.tfvars.example     # Template — copy to terraform.tfvars
├── .gitignore
├── modules/
│   ├── vpc/                     # Custom VPC — 9 subnets, NAT, IGW, routes
│   ├── eks/                     # EKS cluster, node group, OIDC, add-ons
│   ├── rds/                     # PostgreSQL 15 — data subnet, gp3, encrypted
│   ├── elasticache/             # Redis 7 — data subnet, lru eviction
│   ├── ecr/                     # 4 ECR repos with lifecycle policies
│   ├── irsa/                    # IAM roles for ALB, ExternalDNS, ESO
│   ├── secrets/                 # AWS Secrets Manager — all finpay secrets
│   └── helm/                    # All Helm releases — ALB, Istio, ArgoCD,
│                                #   RabbitMQ, Prometheus+Grafana, Kiali
└── scripts/
    ├── bootstrap.sh             # Create S3 + DynamoDB for state (run once)
    └── destroy.sh               # Safe teardown in correct dependency order
```

## Related repos

- [`finpay-api`](https://github.com/your-org/finpay-api) — microservice source code
- [`finpay-gitops`](https://github.com/your-org/finpay-gitops) — K8s manifests, ArgoCD apps
- [`finpay-infrastructure`](https://github.com/devopschroniclesGit/finpay-infrastructure) — original Elastic Beanstalk setup (untouched)
