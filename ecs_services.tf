locals {
  nurax_instances = {
    "${var.namespace}-dev" = {}
    "${var.namespace}-pg" = {}
    "${var.namespace}-stable" = {}
  }
}

resource "aws_acm_certificate" "nurax_certificate" {
  domain_name                 = aws_route53_zone.public_zone.name
  subject_alternative_names   = [for hostname in keys(local.nurax_instances): "${hostname}.${var.hosted_zone_name}"]
  validation_method           = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

module "nurax_instance" {
  for_each    = local.nurax_instances
  source      = "./modules/nurax_ecs_service"

  container_config = {
    data_volume_id            = aws_efs_file_system.nurax_data_volume.id
    database_url              = "postgres://${aws_db_instance.db.username}:${random_string.db_master_password.result}@${aws_db_instance.db.address}:${aws_db_instance.db.port}/${each.key}"
    db_pool_size              = 20
    fedora_base_path          = "/${each.key}"
    fedora_url                = "${local.samvera_stack_base_url}:8080/rest"
    honeybadger_api_key       = var.honeybadger_api_key
    honeybadger_environment   = each.key
    redis_host                = aws_elasticache_cluster.redis.cache_nodes[0].address
    redis_port                = "6379"
    region                    = data.aws_region.current.name
    solr_url                  = "${local.samvera_stack_base_url}:8983/solr/${each.key}"
  }

  acm_certificate_arn   = aws_acm_certificate.nurax_certificate.arn
  cpu                   = 4096
  memory                = 8192
  namespace             = each.key
  private_subnets       = module.vpc.private_subnets
  public_subnets        = module.vpc.public_subnets
  registry_url          = local.ecs_registry_url
  security_group_ids    = [aws_security_group.nurax.id]
  execution_role_arn    = aws_iam_role.task_execution_role.arn
  task_role_arn         = aws_iam_role.nurax_role.arn
  vpc_id                = module.vpc.vpc_id
}