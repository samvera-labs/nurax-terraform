variable "acm_certificate_arn" {
  type = string
}

variable "container_config" {
  type = map(string)
}

variable "cpu" {
  type = number
}

variable "execution_role_arn" {
  type  = string
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
