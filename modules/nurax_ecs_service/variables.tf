variable "acm_certificate_arn" {
  type = string
}

variable "container_config" {
  type = map(string)
}

variable "cpu" {
  type = number
}

variable "dns_name" {
  type = string
}

variable "efs_data_access_point" {
  type = string
}

variable "efs_tmp_access_point" {
  type = string
}

variable "efs_clamav_access_point" {
  type = string
}

variable "execution_role_arn" {
  type = string
}

variable "extra_environment" {
  type    = map(string)
  default = {}
}

variable "lb_security_group_id" {
  type = string
}

variable "memory" {
  type = number
}

variable "namespace" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "public_subnets" {
  type = list(string)
}

variable "public_zone_id" {
  type = string
}

variable "registry_url" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "task_role_arn" {
  type = string
}

variable "vpc_id" {
  type = string
}
