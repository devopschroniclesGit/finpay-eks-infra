variable "app_name" {
  type = string
}
variable "environment" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "data_subnet_ids" {
  type = list(string)
}
variable "eks_node_sg_id" {
  type = string
}
variable "redis_node_type" {
  type    = string
  default = "cache.t3.micro"
}
