
locals {
  common_environment = [
    { name="AWS_REGION",                  value = var.container_config.region },
    { name="DATABASE_URL",                value = "${var.container_config.database_url}?pool=${var.container_config.db_pool_size}" },
    { name="FEDORA_BASE_PATH",            value = var.container_config.fedora_base_path },
    { name="FEDORA_URL",                  value = var.container_config.fedora_url },
    { name="HONEYBADGER_API_KEY",         value = var.container_config.honeybadger_api_key },
    { name="HONEYBADGER_ENV",             value = var.container_config.honeybadger_environment },
    { name="HYRAX_CACHE_PATH",            value = "/var/nurax-data/cache" },
    { name="HYRAX_DERIVATIVES_PATH",      value = "/var/nurax-data/derivatives" },
    { name="HYRAX_STORAGE_PATH",          value = "/var/nurax-data/storage" },
    { name="HYRAX_UPLOAD_PATH",          value = "/var/nurax-data/uploads" },
    { name="RACK_ENV",                    value = "production" },
    { name="RAILS_ENV",                   value = "production" },
    { name="RAILS_LOG_TO_STDOUT",         value = "true" },
    { name="RAILS_SERVE_STATIC_FILES",    value = "true" },
    { name="REDIS_HOST",                  value = var.container_config.redis_host },
    { name="REDIS_PORT",                  value = var.container_config.redis_port },
    { name="REDIS_URL",                   value = "redis://${var.container_config.redis_host}:${var.container_config.redis_port}/" },
    { name="SECRET_KEY_BASE",             value = random_id.secret_key_base.hex },
    { name="SOLR_URL",                    value = var.container_config.solr_url }
  ]

  extra_environment = [for k, v in var.extra_environment: { name=k, value=v }]
  container_environment = concat(local.common_environment, local.extra_environment)

  containers = {
    webapp = { role = "server", ports = [3000] }
    worker = { role = "sidekiq", ports = [] }
  }

  container_definitions = [
    for name, config in local.containers: {
      name                = name
      image               = "${var.registry_url}/${join(":", split("-", var.namespace))}"
      cpu                 = var.cpu / 2
      memoryReservation   = var.memory / 2
      mountPoints         = []
      essential           = true
      environment         = concat(local.container_environment, [{ name = "CONTAINER_ROLE", value = config.role }])
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group           = aws_cloudwatch_log_group.this_logs.name
          awslogs-region          = var.container_config.region
          awslogs-stream-prefix   = name
        }
      }
      portMappings = [
        for port in config.ports: { 
          containerPort: port
          hostPort: port
          protocol = "tcp"
        }
      ]
      mountPoints = [
        {
          "sourceVolume": "nurax-data",
          "containerPath": "/var/nurax-data"
        },
        {
          "sourceVolume": "nurax-temp",
          "containerPath": "/tmp"
        }
      ]
    }
  ]
}

resource "aws_ecs_task_definition" "this_task_definition" {
  family                   = var.namespace
  container_definitions    = jsonencode(local.container_definitions)

  volume {
    name = "nurax-data"
    efs_volume_configuration {
      file_system_id = var.container_config.data_volume_id
      root_directory = "/${var.namespace}"
    }
  }

  volume {
    name = "nurax-temp"
    efs_volume_configuration {
      file_system_id = var.container_config.data_volume_id
      root_directory = "/tmp/${var.namespace}"
    }
  }

  task_role_arn            = var.task_role_arn
  execution_role_arn       = var.execution_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
}

resource "aws_ecs_service" "this_service" {
  name                              = var.namespace
  cluster                           = "nurax"
  task_definition                   = aws_ecs_task_definition.this_task_definition.arn
  desired_count                     = 0
  enable_execute_command            = true
  launch_type                       = "FARGATE"
  platform_version                  = "1.4.0"

  load_balancer {
    target_group_arn = aws_lb_target_group.this_target.arn
    container_name   = "webapp"
    container_port   = 3000
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  network_configuration {
    subnets          = var.public_subnets
    security_groups  = var.security_group_ids
    assign_public_ip = true
  }
}

resource "aws_route53_record" "this_dns_record" {
  zone_id   = var.public_zone_id
  name      = var.dns_name
  type      = "A"

  alias {
    name                      = aws_lb.this_load_balancer.dns_name
    zone_id                   = aws_lb.this_load_balancer.zone_id
    evaluate_target_health    = false
  }
}