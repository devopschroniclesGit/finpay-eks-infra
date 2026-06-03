# ── RDS Security Group ────────────────────────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = "${var.app_name}-rds-sg"
  description = "FinPay RDS — allow inbound from EKS nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-rds-sg" }
}

# ── Subnet Group — data subnets only ─────────────────────────────────────────

resource "aws_db_subnet_group" "finpay" {
  name        = "${var.app_name}-db-subnet-group"
  description = "FinPay RDS subnet group — data subnets, no internet route"
  subnet_ids  = var.data_subnet_ids

  tags = { Name = "${var.app_name}-db-subnet-group" }
}

# ── Parameter Group ───────────────────────────────────────────────────────────

resource "aws_db_parameter_group" "finpay" {
  name   = "${var.app_name}-postgres15"
  family = "postgres15"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"   # Log queries over 1 second
  }
}

# ── RDS Instance ──────────────────────────────────────────────────────────────

resource "aws_db_instance" "finpay" {
  identifier = "${var.app_name}-postgres"

  # Engine — same version as original
  engine         = "postgres"
  engine_version = var.db_engine_version

  # Upgraded from t3.micro → t3.medium for EKS workloads
  instance_class = var.db_instance_class

  # Storage
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100   # Auto-scale up to 100GB
  storage_type          = "gp3" # gp3 is cheaper and faster than gp2
  storage_encrypted     = true

  # Database
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network — private data subnets, NOT publicly accessible
  db_subnet_group_name   = aws_db_subnet_group.finpay.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Parameter group
  parameter_group_name = aws_db_parameter_group.finpay.name

  # Backups
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Performance Insights — free tier available on t3.medium
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # Protection — false for demo so destroy works cleanly
  deletion_protection = false
  skip_final_snapshot = true

  tags = { Name = "${var.app_name}-postgres" }
}
