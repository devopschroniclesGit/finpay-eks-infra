output "redis_endpoint" {
  value     = aws_elasticache_replication_group.finpay.primary_endpoint_address
  sensitive = true
}
