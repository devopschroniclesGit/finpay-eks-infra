# ── Core ──────────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region — change this to move the entire stack"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "app_name" {
  description = "Application name — used as prefix for all resources"
  type        = string
  default     = "finpay"
}

# ── VPC ───────────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the custom VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy into — 3 recommended for EKS HA"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# ── EKS ───────────────────────────────────────────────────────────────────────

variable "eks_cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
  default     = "t3.xlarge"   # 4 vCPU / 16GB — fits Istio + ArgoCD + Grafana + RabbitMQ
}

variable "eks_node_min_size" {
  description = "Minimum nodes in node group"
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum nodes in node group"
  type        = number
  default     = 5
}

variable "eks_node_desired_size" {
  description = "Desired nodes at launch"
  type        = number
  default     = 3
}

# ── RDS ───────────────────────────────────────────────────────────────────────

variable "db_instance_class" {
  description = "RDS instance class — upgraded from t3.micro for EKS workloads"
  type        = string
  default     = "db.t3.medium"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "finpay_db"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "finpay_user"
}

variable "db_password" {
  description = "PostgreSQL master password — set via TF_VAR_db_password, never hardcode"
  type        = string
  sensitive   = true
}

variable "db_allocated_storage" {
  description = "RDS storage in GB"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15"
}

# ── ElastiCache ───────────────────────────────────────────────────────────────

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

# ── App secrets ───────────────────────────────────────────────────────────────

variable "jwt_secret" {
  description = "JWT signing secret — minimum 64 chars. Generate: node -e \"console.log(require('crypto').randomBytes(64).toString('hex'))\""
  type        = string
  sensitive   = true
}

variable "jwt_expires_in" {
  description = "JWT token expiry"
  type        = string
  default     = "7d"
}

variable "rabbitmq_password" {
  description = "RabbitMQ admin password"
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = "changeme-update-this"
}

# ── GitHub ────────────────────────────────────────────────────────────────────

variable "github_repo" {
  description = "GitHub source repo — format: owner/repo"
  type        = string
  default     = "devopschroniclesGit/finpay-api"
}

variable "github_branch" {
  description = "GitHub branch CI watches"
  type        = string
  default     = "main"
}
