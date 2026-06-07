# finpay-eks-infra

Terraform infrastructure for FinPay microservices on AWS EKS.
Evolved from `finpay-infrastructure` (Elastic Beanstalk monolith) → full Kubernetes microservices stack.

## What this provisions

| Resource | Type | Description |
|---|---|---|
| VPC | Custom 10.0.0.0/16 | 3 public + 3 private + 3 data subnets across 3 AZs |
| EKS | 1.30 — t3.xlarge ×3 | Kubernetes cluster with managed node group |
| RDS | db.t3.medium PostgreSQL 15 | Private data subnet, gp3, encrypted, Performance Insights |
| ElastiCache | cache.t3.micro Redis 7 | Rate limiting + balance caching |
| ECR | 7 repositories | auth, account, transaction, notification, api, web, rabbitmq |
| AWS Secrets Manager | finpay/production | DATABASE_URL, REDIS_URL, JWT_SECRET, RABBITMQ_URL |
| IRSA | 3 roles | ALB controller, ExternalDNS, External Secrets Operator |
| ALB Controller | Helm | AWS Load Balancer Controller for Ingress |
| Istio | 1.20 | Service mesh — mTLS, traffic management |
| ArgoCD | 6.7 | GitOps — watches finpay-gitops repo, syncs to cluster |
| RabbitMQ | Plain StatefulSet | Official rabbitmq:3.13-management image mirrored to ECR |
| Prometheus + Grafana | kube-prometheus-stack | Full observability stack |
| Kiali | 1.80 | Istio service mesh visualisation |

## Architecture

```
Users
  │
  ▼
AWS ALB (internet-facing)
  │
  ├── /api/v1/auth         → auth-service     :3001
  ├── /api/v1/accounts     → account-service  :3002
  ├── /api/v1/transactions → transaction-service :3003
  └── /api/v1/health       → auth-service     :3001

  finpay-web (React + Vite)  → separate ALB

  transaction-service → RabbitMQ → notification-service

  All services → RDS PostgreSQL (data subnet)
  account + transaction → ElastiCache Redis (data subnet)

  GitHub Actions → ECR → finpay-gitops → ArgoCD → EKS
```

## Prerequisites

```bash
# Required tools
aws --version          # AWS CLI configured with us-east-1
terraform --version    # >= 1.5.0
kubectl version        # any recent version
helm version           # >= 3.0
docker --version       # for building images
```

## First time setup (run once)

```bash
git clone https://github.com/devopschroniclesGit/finpay-eks-infra
cd finpay-eks-infra

# Create S3 bucket for Terraform state
bash scripts/bootstrap.sh

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in passwords and secrets

# Initialise Terraform
terraform init

# Deploy (~20-25 minutes)
terraform apply --auto-approve

# Run post-apply setup
GRAFANA_PASSWORD=FinPay@Graf2024! bash scripts/post-apply.sh
```

## Daily workflow

Lambda destroys all resources at 8am SAST daily.

```bash
# Morning — rebuild everything
cd ~/finpay-eks-infra
sudo chronyc makestep
terraform apply --auto-approve
GRAFANA_PASSWORD=FinPay@Graf2024! bash scripts/post-apply.sh

# Evening — destroy to save costs
bash scripts/destroy.sh
```

## post-apply.sh does

1. Syncs clock (prevents AWS signature errors)
2. Configures kubectl
3. Attaches AmazonEBSCSIDriverPolicy to node role + installs EBS CSI addon
4. Adds RDS and Redis security group rules from EKS cluster SG
5. Labels finpay namespace for Istio sidecar injection
6. Deploys RabbitMQ as plain StatefulSet using ECR image
7. Installs Prometheus + Grafana via Helm
8. Applies ClusterSecretStore for External Secrets Operator
9. Creates ArgoCD applications (finpay-prod + finpay-web)
10. Applies ALB ingresses for ArgoCD and Grafana
11. Seeds database with alice and bob demo accounts
12. Rebuilds finpay-web Docker image with new API ALB URL

## Platform URLs

URLs change after every rebuild. Run after post-apply.sh:

```bash
kubectl get ingress -A
```

| Service | Ingress name | Namespace |
|---|---|---|
| FinPay API | finpay-ingress | finpay |
| FinPay Web UI | finpay-web | finpay |
| ArgoCD | argocd-ingress | argocd |
| Grafana | grafana-ingress | monitoring |

## Demo accounts

| Email | Password | Balance |
|---|---|---|
| alice@finpay.dev | password123 | ZAR 10,000 |
| bob@finpay.dev | password123 | ZAR 5,000 |

Bob's account ID: `f267bce9-9464-4783-b294-b5827cba2293`

## Known issues

| Issue | Workaround |
|---|---|
| RabbitMQ notification-service restarts | Reconnect logic needed — service still works |
| Old finpay-api deployment still running | Remove deployment.yaml from GitOps base |
| ALB URLs change after every rebuild | Add Route53 custom domain |
| No persistent logs | Add Loki + Fluent Bit |

## Security groups (managed by post-apply.sh)

These rules are added automatically by post-apply.sh:

| SG | Rule | Source |
|---|---|---|
| RDS sg-0c3208c93bfdc4622 | TCP 5432 | EKS cluster SG |
| ElastiCache sg-0b429cc0fa7b3c1a2 | TCP 6379 | EKS cluster SG |

## File structure

```
finpay-eks-infra/
├── main.tf                      # Root — providers, S3 backend, module calls
├── variables.tf                 # All input variables
├── outputs.tf                   # Cluster endpoint, ECR URLs, next steps
├── terraform.tfvars.example     # Template — copy to terraform.tfvars
├── .gitignore
├── modules/
│   ├── vpc/                     # Custom VPC — 9 subnets, NAT, IGW, routes
│   ├── eks/                     # EKS 1.30, node group, OIDC provider
│   ├── rds/                     # PostgreSQL 15 — data subnet, encrypted
│   ├── elasticache/             # Redis 7 — data subnet, allkeys-lru
│   ├── ecr/                     # 7 ECR repos with lifecycle policies
│   ├── irsa/                    # IAM roles — ALB, ExternalDNS, ESO
│   ├── secrets/                 # AWS Secrets Manager — all finpay secrets
│   └── helm/                    # ALB controller, Istio, ArgoCD, ESO, Kiali
└── scripts/
    ├── bootstrap.sh             # Create S3 state bucket (run once)
    ├── post-apply.sh            # Full cluster setup after terraform apply
    └── destroy.sh               # Safe teardown with dependency handling
```

## Related repos

| Repo | Purpose |
|---|---|
| [finpay-microservices](https://github.com/devopschroniclesGit/finpay-microservices) | 4 Node.js microservices |
| [finpay-gitops](https://github.com/devopschroniclesGit/finpay-gitops) | K8s manifests + ArgoCD apps |
| [finpay-web](https://github.com/devopschroniclesGit/finpay-web) | React + Vite frontend |
| [finpay-api](https://github.com/devopschroniclesGit/finpay-api) | Original monolith (source of split) |
| [finpay-infrastructure](https://github.com/devopschroniclesGit/finpay-infrastructure) | Original Elastic Beanstalk setup |
