module "vpc" {
  source    = "terraform-aws-modules/vpc/aws"
  version   = "3.7.0"

  name = "${var.namespace}-vpc"
  cidr = var.cidr_block

  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  
  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_nat_gateway   = false
  enable_vpn_gateway   = false

  create_database_subnet_group = false

  private_subnet_tags = {
    SubnetType = "private"
  }

  public_subnet_tags = {
    SubnetType = "public"
  }

  }

resource "aws_security_group" "endpoint_access" {
  name        = "${var.namespace}-endpoints"
  description = "VPC Endpoint Security Group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.cidr_block]
  }
}

resource "aws_security_group" "ssh" {
  name        = "${var.namespace}-ssh"
  description = "Security Group for public-facing SSH"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "endpoints" {
  source    = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version   = "3.7.0"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.vpc.default_security_group_id, aws_security_group.endpoint_access.id]
  endpoints = {
    s3 = {
      # interface endpoint
      route_table_ids   = [module.vpc.vpc_main_route_table_id]
      service           = "s3"
      service_type      = "Gateway"
    }

    ssmmessages = {
      service             = "ssmmessages"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
    }
  }
}
