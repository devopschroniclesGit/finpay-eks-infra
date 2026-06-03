output "alb_controller_role_arn" { value = aws_iam_role.alb_controller.arn }
output "externaldns_role_arn"    { value = aws_iam_role.externaldns.arn }
output "eso_role_arn"            { value = aws_iam_role.eso.arn }
