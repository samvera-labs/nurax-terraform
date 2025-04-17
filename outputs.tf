locals {
  samvera_stack_hostname = join(".", [aws_service_discovery_service.samvera_stack.name, aws_service_discovery_private_dns_namespace.private_service_discovery.name])
  samvera_stack_base_url = "${local.samvera_stack_hostname}"
  fcrepo_hostname = join(".", [aws_service_discovery_service.fcrepo.name, aws_service_discovery_private_dns_namespace.private_service_discovery.name])
  fcrepo_base_url = "http://${local.fcrepo_hostname}"
}

output "nurax_url" {
  value = { for k, v in module.nurax_instance: k => v.endpoint }
}
