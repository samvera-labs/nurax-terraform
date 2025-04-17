resource "aws_cloudwatch_log_group" "samvera_stack_logs" {
  name                = "/ecs/samvera-stack"
  retention_in_days   = 3
}

resource "aws_security_group" "samvera_stack_service" {
  name        = "${var.namespace}-samvera-stack"
  description = "Fedora/Solr Service Security Group"
  vpc_id      = module.vpc.vpc_id
  timeouts {
    delete = "2m"
  }
}

resource "aws_security_group_rule" "samvera_stack_service_egress" {
  security_group_id   = aws_security_group.samvera_stack_service.id
  type                = "egress"
  from_port           = 0
  to_port             = 65535
  protocol            = "tcp"
  cidr_blocks         = [module.vpc.vpc_cidr_block]
}

resource "aws_security_group_rule" "samvera_stack_service_ingress" {
  for_each            = toset(["8080", "8983"])
  security_group_id   = aws_security_group.samvera_stack_service.id
  type                = "ingress"
  from_port           = each.key
  to_port             = each.key
  protocol            = "tcp"
  cidr_blocks         = [module.vpc.vpc_cidr_block]
}

resource "aws_s3_bucket" "fedora6_ocfl" {
  bucket      = "${var.namespace}-fcrepo6-ocfl"
}

resource "aws_iam_user" "fedora6_binary_bucket_user" {
  name = "${var.namespace}-fcrepo6"
  path = "/system/"
}

resource "aws_iam_access_key" "fedora6_binary_bucket_access_key" {
  user = aws_iam_user.fedora6_binary_bucket_user.name
}

resource "aws_iam_user_policy" "fedora6_binary_bucket_user_policy" {
  name = "${var.namespace}-fcrepo6"
  user = aws_iam_user.fedora6_binary_bucket_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "1"
        Effect = "Allow"
        Action = ["s3:*"]

        Resource = [
          "${aws_s3_bucket.fedora6_ocfl.arn}",
          "${aws_s3_bucket.fedora6_ocfl.arn}/*"
        ]
      }
    ]
  })
}

resource "random_string" "fcrepo6_password" {
  length  = 16
  upper   = true
  lower   = true
  numeric = true
  special = false
}

resource "aws_lambda_invocation" "create_fedora6_database" {
  function_name = module.create_db_lambda.lambda_function_arn

  input = jsonencode({
    host              = aws_db_instance.db.address
    port              = aws_db_instance.db.port
    user              = aws_db_instance.db.username
    password          = aws_db_instance.db.password
    schema            = "fcrepo6"
    schema_password   = random_string.fcrepo6_password.result
  })
}

locals {
  create_fedora6_database_result = jsondecode(aws_lambda_invocation.create_fedora6_database.result)

  fedora6_catalina_opts = {
    "Dfcrepo.aws.access-key" = aws_iam_access_key.fedora6_binary_bucket_access_key.id
    "Dfcrepo.aws.secret-key" = aws_iam_access_key.fedora6_binary_bucket_access_key.secret
    "Dfcrepo.aws.region" = data.aws_region.current.name
    "Dfcrepo.home" = "/fcrepo-home"
    "Dfcrepo.jms.enabled" = "false"
    "Dfcrepo.log" = "WARN"
    "Dfcrepo.metrics.enable" = "false"
    "Dfcrepo.ocfl.s3.bucket" = aws_s3_bucket.fedora6_ocfl.id
    "Dfcrepo.ocfl.s3.prefix" = var.namespace
    "Dfcrepo.pid.minter.count" = "4"
    "Dfcrepo.pid.minter.length" = "2"
    "Dfcrepo.postgresql.host" = aws_db_instance.db.address
    "Dfcrepo.postgresql.port" = aws_db_instance.db.port
    "Dfcrepo.postgresql.username" = local.create_fedora6_database_result.username
    "Dfcrepo.postgresql.password" = local.create_fedora6_database_result.password
    "Dfcrepo.storage" = "ocfl-s3"
    "Dfile.encoding" = "UTF-8"
    # Extra values here because they have no =
    "Djava.awt.headless" = "true -server -Xms1G -Xmx2G -XX:+UseG1GC -XX:+DisableExplicitGC"
  }
}

resource "aws_efs_file_system" "samvera_stack_data_volume" {
  encrypted      = false
}

resource "aws_efs_access_point" "solr_data" {
  file_system_id    = aws_efs_file_system.samvera_stack_data_volume.id
  posix_user {
    uid = 8983
    gid = 0
  }
  root_directory {
    path = "/solr-data"
    creation_info {
      owner_uid   = 8983
      owner_gid   = 0
      permissions = "0770"
    }
  }
}

resource "aws_efs_access_point" "fcrepo6_data" {
  file_system_id    = aws_efs_file_system.samvera_stack_data_volume.id
  posix_user {
    uid = 0
    gid = 0
  }
  root_directory {
    path = "/fcrepo6-data"
    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "0770"
    }
  }
}

resource "aws_efs_mount_target" "samvera_stack_data_mount_target" {
  for_each          = toset(module.vpc.private_subnets)
  file_system_id    = aws_efs_file_system.samvera_stack_data_volume.id
  security_groups   = [
    aws_security_group.samvera_stack_data_access.id
  ]
  subnet_id         = each.key
}

resource "aws_security_group" "samvera_stack_data_access" {
  name        = "${var.namespace}-stack-data"
  description = "Samvera Stack Data Volume Security Group"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "samvera_stack_data_egress" {
  security_group_id   = aws_security_group.samvera_stack_data_access.id
  type                = "egress"
  from_port           = 0
  to_port             = 65535
  protocol            = -1
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "samvera_stack_data_ingress" {
  security_group_id           = aws_security_group.samvera_stack_data_access.id
  type                        = "ingress"
  from_port                   = 2049
  to_port                     = 2049
  protocol                    = "tcp"
  source_security_group_id    = aws_security_group.samvera_stack_service.id
}

resource "aws_security_group_rule" "nurax_console_stack_data_ingress" {
  security_group_id           = aws_security_group.samvera_stack_data_access.id
  type                        = "ingress"
  from_port                   = 2049
  to_port                     = 2049
  protocol                    = "tcp"
  source_security_group_id    = aws_security_group.nurax_console.id
}

resource "aws_ecs_task_definition" "samvera_stack" {
  family = "${var.namespace}-samvera-stack"
  
  container_definitions = jsonencode([
    {
      name                = "fcrepo6"
      image               = "${local.ecs_registry_url}/fcrepo:6.5.1-tomcat9"
      essential           = true
      cpu                 = 1024
      memory              = 2048
      environment = [
        {
          name  = "CATALINA_OPTS",
          value = join(" ", [for key, value in local.fedora6_catalina_opts : "-${key}=${value}"])
        },
        {
          name  = "ENCODED_SOLIDUS_HANDLING",
          value = "passthrough"
        }
      ]
      portMappings = [
        { hostPort = 8080, containerPort = 8080 }
      ]
      mountPoints = [
        { sourceVolume = "fcrepo6-data", containerPath = "/fcrepo-home" }
      ]
      readonlyRootFilesystem = false
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = aws_cloudwatch_log_group.samvera_stack_logs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "fcrepo6"
        }
      }
      # For some reason the health check on this never seems to succeed so let's just turn it off for now
      # healthCheck = {
      #   command  = ["CMD-SHELL", "wget -q -O /dev/null --method=OPTIONS http://localhost:8080/rest/"]
      #   interval        = 30
      #   retries         = 3
      #   timeout         = 5
      #   startPeriod     = 300
      # }
    },
    {
      name                = "solr",
      image               = "${local.ecs_registry_url}/solr:8.11-slim"
      essential           = true
      cpu                 = 1024
      memory              = 2048
      command             = ["solr", "-f", "-q"]
      environment = [
        { name = "SOLR_HEAP",       value = "${2048 * 0.9765625}m" }
      ]
      portMappings = [
        { hostPort = 8983, containerPort = 8983 }
      ]
      mountPoints = [
        { sourceVolume = "solr-data", containerPath = "/var/solr/data" }
      ]
      readonlyRootFilesystem = false
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = aws_cloudwatch_log_group.samvera_stack_logs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "solr"
        }
      }
      healthCheck = {
        command  = ["CMD-SHELL", "wget -q -O - http://localhost:8983/solr/nurax-dev/admin/ping http://localhost:8983/solr/nurax-pg/admin/ping"]
        interval = 30
        retries  = 3
        timeout  = 5
      }
    }
  ])

  volume {
    name        = "solr-data"
    efs_volume_configuration {
      file_system_id            = aws_efs_file_system.samvera_stack_data_volume.id
      # root_directory        = "/solr-data"
      transit_encryption        = "ENABLED"
      # transit_encryption_port   = 2889

      authorization_config {
        access_point_id = aws_efs_access_point.solr_data.id
      }
    }
  }

  volume {
    name = "fcrepo6-data"
    efs_volume_configuration {
      file_system_id            = aws_efs_file_system.samvera_stack_data_volume.id
      # root_directory        = "/fcrepo6-data"
      transit_encryption        = "ENABLED"
      # transit_encryption_port   = 2890

      authorization_config {
        access_point_id = aws_efs_access_point.fcrepo6_data.id
      }
    }
  }

  task_role_arn            = aws_iam_role.task_execution_role.arn
  execution_role_arn       = aws_iam_role.task_execution_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 2048
  memory                   = 4096
}

resource "aws_ecs_service" "samvera_stack" {
  name                   = "samvera-stack"
  cluster                = aws_ecs_cluster.nurax_cluster.id
  task_definition        = aws_ecs_task_definition.samvera_stack.arn
  desired_count          = 1
  enable_execute_command = true
  launch_type            = "FARGATE"
  platform_version       = "1.4.0"

  lifecycle {
    ignore_changes          = [desired_count]
    replace_triggered_by = [
      aws_security_group.samvera_stack_service.name
    ]
  }

  network_configuration {
    security_groups  = [
      module.vpc.default_security_group_id,
      aws_security_group.samvera_stack_service.id,
      aws_security_group.endpoint_access.id
    ]
    subnets          = module.vpc.public_subnets
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.samvera_stack.arn
  }
}

resource "aws_service_discovery_service" "samvera_stack" {
  name = "samvera-stack"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.private_service_discovery.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
}
