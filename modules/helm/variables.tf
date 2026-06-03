variable "app_name" {
  type = string
}
variable "environment" {
  type = string
}
variable "cluster_name" {
  type = string
}
variable "aws_region" {
  type = string
}
variable "aws_account_id" {
  type = string
}
variable "vpc_id" {
  type    = string
  default = ""
}
variable "alb_controller_role_arn" {
  type = string
}
variable "externaldns_role_arn" {
  type = string
}
variable "eso_role_arn" {
  type = string
}
variable "rabbitmq_password" {
  type      = string
  sensitive = true
}
variable "grafana_admin_password" {
  type      = string
  sensitive = true
}
