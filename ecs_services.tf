locals {
  nurax_instances = {
    "dev" = {
      extra_environment = {
        RAILS_ROOT = "/app/samvera/hyrax-webapp"
      }
    }
    "pg" = {
      extra_environment = {
        RAILS_ROOT = "/app/samvera/hyrax-koppie"
      }
    }
    "f6" = {
      extra_environment = {
        RAILS_ROOT = "/app/samvera/hyrax-koppie"
        VALKYRIE_METADATA_ADAPTER   = "fedora_metadata"
        VALKYRIE_STORAGE_ADAPTER    = "fedora_storage"
      }
    }
  }

  schema_params = {
    for k, v in local.nurax_instances: k => {
      schema            = "${var.namespace}-${k}"
      schema_role       = "${var.namespace}_${k}"
      schema_password   = random_string.nurax_db_password[k].result
    }
  }

  database_urls = {
    for k, v in local.schema_params: 
      k => "postgres://${v.schema_role}:${v.schema_password}@${aws_db_instance.db.address}:${aws_db_instance.db.port}/${v.schema}"
  }
}

resource "aws_acm_certificate" "nurax_certificate" {
  domain_name                 = aws_route53_zone.public_zone.name
  subject_alternative_names   = ["*.${aws_route53_zone.public_zone.name}"]
  validation_method           = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "random_string" "nurax_db_password" {
  for_each    = local.nurax_instances
  length      = 16
  upper       = true
  lower       = true
  numeric     = true
  special     = false
}

resource "aws_lambda_invocation" "create_nurax_database" {
  for_each        = local.nurax_instances
  function_name   = module.create_db_lambda.lambda_function_arn

  input = jsonencode(
    merge(
      local.schema_params[each.key], 
      {
        host              = aws_db_instance.db.address
        port              = aws_db_instance.db.port
        user              = aws_db_instance.db.username
        password          = aws_db_instance.db.password
      }
    )
  )
}

resource "aws_efs_access_point" "nurax_data" {
  for_each        = local.nurax_instances
  file_system_id    = aws_efs_file_system.nurax_data_volume.id
  posix_user {
    uid = 0
    gid = 0
  }
  root_directory {
    path = "/nurax-${each.key}"
    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "0770"
    }
  }
}

resource "aws_efs_access_point" "nurax_tmp" {
  for_each        = local.nurax_instances
  file_system_id    = aws_efs_file_system.nurax_data_volume.id
  posix_user {
    uid = 0
    gid = 0
  }
  root_directory {
    path = "/tmp/nurax-${each.key}"
    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "0770"
    }
  }
}

resource "aws_efs_access_point" "nurax_clamav" {
  for_each        = local.nurax_instances
  file_system_id    = aws_efs_file_system.nurax_data_volume.id
  posix_user {
    uid = 0
    gid = 0
  }
  root_directory {
    path = "/clamav/nurax-${each.key}"
    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "0770"
    }
  }
}

module "nurax_instance" {
  for_each    = local.nurax_instances
  source      = "./modules/nurax_ecs_service"

  container_config = {
    data_volume_id            = aws_efs_file_system.nurax_data_volume.id
    database_hostname         = aws_db_instance.db.address
    database_port             = aws_db_instance.db.port
    database_url              = local.database_urls[each.key]
    db_pool_size              = 20
    fedora_base_path          = "/${var.namespace}-${each.key}"
    fedora_url                = "${local.fcrepo_base_url}:8080/rest"
    fedora6_url               = "http://fedoraAdmin:fedoraAdmin@${local.samvera_stack_base_url}:8080/fcrepo/rest"
    honeybadger_api_key       = var.honeybadger_api_key
    honeybadger_environment   = each.key
    redis_host                = aws_elasticache_cluster.redis[each.key].cache_nodes[0].address
    redis_port                = aws_elasticache_cluster.redis[each.key].cache_nodes[0].port
    region                    = data.aws_region.current.name
    solr_url                  = "http://${local.samvera_stack_base_url}:8983/solr/${var.namespace}-${each.key}"
    samvera_stack_hostname    = local.samvera_stack_hostname
    working_dir               = each.key == "dev" ? "/app/samvera/hyrax-webapp" : "/app/samvera/hyrax-koppie"
  }

  acm_certificate_arn     = aws_acm_certificate.nurax_certificate.arn
  cpu                     = 1024
  memory                  = 2048
  dns_name                = each.key
  namespace               = "${var.namespace}-${each.key}"
  private_subnets         = module.vpc.private_subnets
  public_subnets          = module.vpc.public_subnets
  public_zone_id          = aws_route53_zone.public_zone.id
  registry_url            = local.ecs_registry_url
  lb_security_group_id    = aws_security_group.nurax_load_balancer.id
  execution_role_arn      = aws_iam_role.task_execution_role.arn
  task_role_arn           = aws_iam_role.nurax_role.arn
  vpc_id                  = module.vpc.vpc_id
  extra_environment       = try(each.value.extra_environment, {})
  efs_data_access_point   = aws_efs_access_point.nurax_data[each.key].id
  efs_tmp_access_point    = aws_efs_access_point.nurax_tmp[each.key].id
  efs_clamav_access_point = aws_efs_access_point.nurax_clamav[each.key].id

  security_group_ids    = [
    module.vpc.default_security_group_id,
    aws_security_group.nurax.id
  ]
}