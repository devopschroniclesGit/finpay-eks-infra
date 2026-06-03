output "db_endpoint" {
  value     = aws_db_instance.finpay.endpoint
  sensitive = true
}
output "db_name" { value = aws_db_instance.finpay.db_name }
