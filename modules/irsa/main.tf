# ── IRSA — IAM Roles for Service Accounts ────────────────────────────────────
# Allows pods to assume IAM roles without node-level credentials

locals {
  oidc_sub = replace(var.cluster_oidc_url, "https://", "")
}

# ── ALB Ingress Controller ────────────────────────────────────────────────────

resource "aws_iam_role" "alb_controller" {
  name = "${var.app_name}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_sub}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_sub}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "alb_controller" {
  name   = "${var.app_name}-alb-controller-policy"
  policy = file("${path.module}/policies/alb-controller.json")
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# ── ExternalDNS ───────────────────────────────────────────────────────────────

resource "aws_iam_role" "externaldns" {
  name = "${var.app_name}-externaldns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_sub}:sub" = "system:serviceaccount:kube-system:external-dns"
          "${local.oidc_sub}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "externaldns" {
  name = "${var.app_name}-externaldns-policy"
  role = aws_iam_role.externaldns.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListResourceRecordSets"]
        Resource = ["*"]
      }
    ]
  })
}

# ── External Secrets Operator ─────────────────────────────────────────────────
# Allows ESO to pull secrets from AWS Secrets Manager

resource "aws_iam_role" "eso" {
  name = "${var.app_name}-eso-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_sub}:sub" = "system:serviceaccount:external-secrets:external-secrets"
          "${local.oidc_sub}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eso" {
  name = "${var.app_name}-eso-policy"
  role = aws_iam_role.eso.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:finpay/*"
      }
    ]
  })
}
