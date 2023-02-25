locals {
  hosted_subdomain = join(".", [var.namespace, var.hosted_zone_name])
}

resource "aws_route53_zone" "public_zone" {
  name = local.hosted_subdomain
}

resource "aws_service_discovery_private_dns_namespace" "private_service_discovery" {
  name        = "svc.${local.hosted_subdomain}"
  description = "Service Discovery for ${var.namespace}"
  vpc         = module.vpc.vpc_id
}
