# ── ElastiCache Security Group ────────────────────────────────────────────────

resource "aws_security_group" "redis" {
  name        = "${var.app_name}-redis-sg"
  description = "FinPay Redis — allow inbound from EKS nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_node_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-redis-sg" }
}

# ── Subnet Group ──────────────────────────────────────────────────────────────

resource "aws_elasticache_subnet_group" "finpay" {
  name        = "${var.app_name}-redis-subnet-group"
  description = "FinPay Redis subnet group — data subnets"
  subnet_ids  = var.data_subnet_ids
}

# ── Parameter Group ───────────────────────────────────────────────────────────

resource "aws_elasticache_parameter_group" "finpay" {
  name   = "${var.app_name}-redis7"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
}

# ── Redis Cluster ─────────────────────────────────────────────────────────────

resource "aws_elasticache_replication_group" "finpay" {
  replication_group_id = "${var.app_name}-redis"
  description          = "FinPay Redis — rate limiting and caching"

  node_type            = var.redis_node_type
  num_cache_clusters   = 1      # Single node for demo — set to 2+ for HA
  port                 = 6379
  engine_version       = "7.0"
  parameter_group_name = aws_elasticache_parameter_group.finpay.name
  subnet_group_name    = aws_elasticache_subnet_group.finpay.name
  security_group_ids   = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false  # set true if using AUTH token

  automatic_failover_enabled = false  # requires num_cache_clusters >= 2

  tags = { Name = "${var.app_name}-redis" }
}
