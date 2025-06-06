variable "availability_zones" {
  description   = "Availability zones to provision in the VPC"
  type          = list(string)
  default       = ["us-east-2a", "us-east-2b", "us-east-2c"]
}

variable "cidr_block" {
  description   = "CIDR block for the entire VPC"
  type          = string
  default       = "10.1.0.0/16"
}

variable "console_users" {
  description   = "GitHub IDs of users who need access to the Nurax console"
  type          = list(string)
  default       = []
}

variable "db_instance_class" {
  description   = "Instance class for the RDS database"
  type          = string
  default       = "db.t4g.micro"
}

variable "honeybadger_api_key" {
  type    = string
  default = ""
}

variable "hosted_zone_name" {
  description   = "Domain name the stack domain will be created under"
  type          = string
}

variable "namespace" {
  description   = "Prefix for resource in the stack"
  type          = string
  default       = "nurax"
}

variable "postgres_version" {
  description   = "PostgreSQL version to use"
  type          = string
  default       = "14.13"
}

variable "private_subnets" {
  description   = "CIDR blocks for the private subnet in each availability zone"
  type          = list(string)
  default       = ["10.1.1.0/24", "10.1.3.0/24", "10.1.5.0/24"]
}

variable "public_subnets" {
  description   = "CIDR blocks for the public subnet in each availability zone"
  type          = list(string)
  default       = ["10.1.2.0/24", "10.1.4.0/24", "10.1.6.0/24"]
}

variable "tags" {
  description   = "Tags to add to all resources"
  type          = map
  default       = {}
}
