terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  # S3 backend — ACTIVE (run scripts/bootstrap.sh first to create bucket + table)
  backend "s3" {
    bucket       = "finpay-eks-terraform-state"
    key          = "finpay/eks/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

# ── Providers ─────────────────────────────────────────────────────────────────

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "finpay"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "devopschronicles"
      Stack       = "eks"
    }
  }
}

# Helm + Kubernetes providers — wired to EKS after cluster is created
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}


# ── Data sources ──────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Modules ───────────────────────────────────────────────────────────────────

module "vpc" {
  source      = "./modules/vpc"
  app_name    = var.app_name
  environment = var.environment
  aws_region  = var.aws_region
}

module "eks" {
  source          = "./modules/eks"
  app_name        = var.app_name
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnet_ids
  node_instance_type = var.eks_node_instance_type
  node_min_size      = var.eks_node_min_size
  node_max_size      = var.eks_node_max_size
  node_desired_size  = var.eks_node_desired_size
}

module "rds" {
  source            = "./modules/rds"
  app_name          = var.app_name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  data_subnet_ids   = module.vpc.data_subnet_ids
  eks_node_sg_id    = module.eks.node_security_group_id
  db_instance_class = var.db_instance_class
  db_name           = var.db_name
  db_username       = var.db_username
  db_password       = var.db_password
  db_engine_version = var.db_engine_version
}

module "elasticache" {
  source           = "./modules/elasticache"
  app_name         = var.app_name
  environment      = var.environment
  vpc_id           = module.vpc.vpc_id
  data_subnet_ids  = module.vpc.data_subnet_ids
  eks_node_sg_id   = module.eks.node_security_group_id
}

module "ecr" {
  source      = "./modules/ecr"
  app_name    = var.app_name
  environment = var.environment
}

module "irsa" {
  source            = "./modules/irsa"
  app_name          = var.app_name
  environment       = var.environment
  cluster_oidc_url  = module.eks.cluster_oidc_url
  oidc_provider_arn = module.eks.oidc_provider_arn
  aws_account_id    = data.aws_caller_identity.current.account_id
  aws_region        = var.aws_region
}

module "secrets" {
  source          = "./modules/secrets"
  app_name        = var.app_name
  environment     = var.environment
  db_password     = var.db_password
  db_username     = var.db_username
  db_host         = module.rds.db_endpoint
  db_name         = var.db_name
  redis_endpoint  = module.elasticache.redis_endpoint
  jwt_secret      = var.jwt_secret
  rabbitmq_password = var.rabbitmq_password
}

module "helm" {
  source                    = "./modules/helm"
  app_name                  = var.app_name
  environment               = var.environment
  cluster_name              = module.eks.cluster_name
  aws_region                = var.aws_region
  aws_account_id            = data.aws_caller_identity.current.account_id
  alb_controller_role_arn   = module.irsa.alb_controller_role_arn
  externaldns_role_arn      = module.irsa.externaldns_role_arn
  eso_role_arn              = module.irsa.eso_role_arn
  rabbitmq_password         = var.rabbitmq_password
  grafana_admin_password    = var.grafana_admin_password

  depends_on = [module.eks, module.irsa]
}
