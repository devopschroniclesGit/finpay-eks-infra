output "auth_service_url"         { value = aws_ecr_repository.services["auth"].repository_url }
output "account_service_url"      { value = aws_ecr_repository.services["account"].repository_url }
output "transaction_service_url"  { value = aws_ecr_repository.services["transaction"].repository_url }
output "notification_service_url" { value = aws_ecr_repository.services["notification"].repository_url }
