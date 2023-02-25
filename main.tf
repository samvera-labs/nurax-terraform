terraform {
  backend "s3" {
    region = "us-east-2"
  }
  required_providers {
    aws = "~> 4.0"
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = local.tags
  }
}

locals {
  common_tags   = {
    Organization = "Samvera"
    Namespace    = var.namespace
    Git          = "github.com/samvera-labs/nurax-terraform"
    Terraform    = "true"
  }
  tags          = merge(var.tags, local.common_tags)
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
