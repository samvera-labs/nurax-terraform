locals {
  samvera_stack_hostname = join(".", [aws_service_discovery_service.samvera_stack.name, aws_service_discovery_private_dns_namespace.private_service_discovery.name])
  samvera_stack_base_url = "http://${local.samvera_stack_hostname}"
}

output "db" {
  value = {
    host        = aws_db_instance.db.address
    port        = aws_db_instance.db.port
    user        = aws_db_instance.db.username
    password    = random_string.db_master_password.result
  }
}

output "dns_zone" {
  value = aws_route53_zone.public_zone.name
}

output "fedora_url" {
  value = "${local.samvera_stack_base_url}:8080/rest"
}

output "redis_endpoint" {
  value = "${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379"
}

output "solr_url" {
  value = "${local.samvera_stack_base_url}:8983/solr"
}

output "zookeeper_endpoint" {
  value = "${local.samvera_stack_hostname}:9983"
}
