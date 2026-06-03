output "secret_arn"  { value = aws_secretsmanager_secret.finpay.arn }
output "secret_name" { value = aws_secretsmanager_secret.finpay.name }
