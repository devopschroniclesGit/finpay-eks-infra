# ── ECR — one repository per microservice ────────────────────────────────────
# Replaces the single finpay-api repo with per-service repos

locals {
  services = ["auth", "account", "transaction", "notification"]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.services)

  name                 = "${var.app_name}-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true   # Scan every pushed image for CVEs
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${var.app_name}-${each.key}" }
}

# ── Lifecycle Policy — keep last 10 images, auto-delete older ones ────────────

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}
