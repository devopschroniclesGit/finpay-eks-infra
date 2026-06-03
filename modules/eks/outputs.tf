output "cluster_name"           { value = aws_eks_cluster.finpay.name }
output "cluster_endpoint"       { value = aws_eks_cluster.finpay.endpoint }
output "cluster_ca_certificate" { value = aws_eks_cluster.finpay.certificate_authority[0].data }
output "cluster_oidc_url"       { value = aws_eks_cluster.finpay.identity[0].oidc[0].issuer }
output "oidc_provider_arn"      { value = aws_iam_openid_connect_provider.eks.arn }
output "node_security_group_id" { value = aws_security_group.nodes.id }
output "node_role_arn"          { value = aws_iam_role.node.arn }
