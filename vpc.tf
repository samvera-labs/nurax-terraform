data "aws_availability_zones" "available" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source    = "terraform-aws-modules/vpc/aws"
  version   = "5.19.0"

  name = "${var.namespace}-vpc"
  cidr = var.cidr_block

  azs             = local.azs
  private_subnets     = var.private_subnets # [for k, v in local.azs : cidrsubnet(var.cidr_block, 8, k)]
  public_subnets      = var.public_subnets  # [for k, v in local.azs : cidrsubnet(var.cidr_block, 8, k + 4)]
  # private_subnets = var.private_subnets
  # public_subnets  = var.public_subnets
  
  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_nat_gateway   = false
  enable_vpn_gateway   = false

  create_database_subnet_group  = false
  # manage_default_network_acl    = false
  # manage_default_route_table    = false
  # manage_default_security_group = false

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

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

# data "aws_iam_policy_document" "generic_endpoint_policy" {
#   statement {
#     effect    = "Deny"
#     actions   = ["*"]
#     resources = ["*"]
#
#     principals {
#       type        = "*"
#       identifiers = ["*"]
#     }
#
#     condition {
#       test     = "StringNotEquals"
#       variable = "aws:SourceVpc"
#
#       values = [module.vpc.vpc_id]
#     }
#   }
# }

data "aws_iam_policy_document" "vpc_endpoint_policy_s3" {
  version = "2008-10-17"
  statement {
    actions = ["s3:GetObject"]
    effect = "Allow"
    resources = [
      "arn:aws:s3:::prod-${data.aws_region.current.name}-starport-layer-bucket/*",
      "arn:aws:s3:::aws-windows-downloads-${data.aws_region.current.name}/*",
      "arn:aws:s3:::amazon-ssm-${data.aws_region.current.name}/*",
      "arn:aws:s3:::amazon-ssm-packages-${data.aws_region.current.name}/*",
      "arn:aws:s3:::${data.aws_region.current.name}-birdwatcher-prod/*",
      "arn:aws:s3:::aws-ssm-document-attachments-${data.aws_region.current.name}/*",
      "arn:aws:s3:::patch-baseline-snapshot-${data.aws_region.current.name}/*",
      "arn:aws:s3:::aws-ssm-${data.aws_region.current.name}/*",
      "arn:aws:s3:::aws-patchmanager-macos-${data.aws_region.current.name}/*"
    ]
    principals {
      type = "*"
      identifiers = ["*"]
    }
  }

  statement {
    actions = ["*"]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values = [
        data.aws_caller_identity.current.account_id,
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values = [
        data.aws_caller_identity.current.account_id,
      ]
    }
    principals {
      type = "*"
      identifiers = ["*"]
    }
  }
}

module "endpoints" {
  source    = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version   = "5.19.0"

  vpc_id             = module.vpc.vpc_id

  # security_group_ids = [module.vpc.default_security_group_id, aws_security_group.endpoint_access.id]
  security_group_ids = [aws_security_group.endpoint_access.id]
  subnet_ids = module.vpc.private_subnets
  # create_security_group      = true
  # security_group_name_prefix = "${var.namespace}-vpc-endpoints-"
  # security_group_description = "VPC endpoint security group"
  # security_group_rules = {
  #   ingress_https = {
  #     description = "HTTPS from VPC"
  #     cidr_blocks = [module.vpc.vpc_cidr_block]
  #   }
  # }

  endpoints = {
    s3 = {
      # interface endpoint
      route_table_ids   = module.vpc.private_route_table_ids
      service           = "s3"
      policy            = data.aws_iam_policy_document.vpc_endpoint_policy_s3.json
      # private_dns_enabled = true
      # dns_options = {
      #   private_dns_only_for_inbound_resolver_endpoint = false
      # }
      service_type      = "Gateway"
    },

    ecs = {
      service             = "ecs"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    },

    ecs_telemetry = {
      create              = false
      service             = "ecs-telemetry"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    },

    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      # policy              = data.aws_iam_policy_document.generic_endpoint_policy.json
    },

    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      # policy              = data.aws_iam_policy_document.generic_endpoint_policy.json
    },

    logs = {
      service             = "logs"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      # policy              = data.aws_iam_policy_document.generic_endpoint_policy.json
    },

    ssmmessages = {
      service             = "ssmmessages"
      subnet_ids          = module.vpc.private_subnets
      private_dns_enabled = true
    }
  }
}
