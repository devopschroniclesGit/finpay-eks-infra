# ── AWS Secrets Manager ───────────────────────────────────────────────────────
# All secrets stored here — ESO (External Secrets Operator) pulls them
# into Kubernetes Secrets automatically in the finpay namespace

resource "aws_secretsmanager_secret" "finpay" {
  name        = "finpay/production"
  description = "All FinPay EKS application secrets"

  recovery_window_in_days = 0   # Immediate deletion — fine for demo

  tags = { Name = "finpay-production-secrets" }
}

resource "aws_secretsmanager_secret_version" "finpay" {
  secret_id = aws_secretsmanager_secret.finpay.id

  secret_string = jsonencode({
    DATABASE_URL      = "postgresql://${var.db_username}:${var.db_password}@${var.db_host}/${var.db_name}"
    POSTGRES_USER     = var.db_username
    POSTGRES_PASSWORD = var.db_password
    REDIS_URL         = "redis://${var.redis_endpoint}:6379"
    JWT_SECRET        = var.jwt_secret
    RABBITMQ_URL      = "amqp://finpay:${var.rabbitmq_password}@rabbitmq.finpay.svc.cluster.local:5672"
    RABBITMQ_PASSWORD = var.rabbitmq_password
  })
}

# ── Per-service secrets (if needed separately) ────────────────────────────────

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "finpay/jwt"
  description             = "JWT signing secret"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = jsonencode({ JWT_SECRET = var.jwt_secret })
}
