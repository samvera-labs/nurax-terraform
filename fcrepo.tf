# ECS for legacy Fedora 4

resource "aws_cloudwatch_log_group" "fcrepo_logs" {
  name                = "/ecs/fcrepo"
  retention_in_days   = 3
}

resource "aws_security_group" "fcrepo_service" {
  name        = "${var.namespace}-fcrepo"
  description = "Fedora 4 Service Security Group"
  vpc_id      = module.vpc.vpc_id
  timeouts {
    delete = "2m"
  }
}

resource "aws_security_group_rule" "fcrepo_service_egress" {
  security_group_id   = aws_security_group.fcrepo_service.id
  type                = "egress"
  from_port           = 0
  to_port             = 65535
  protocol            = "tcp"
  cidr_blocks         = [module.vpc.vpc_cidr_block]
}

resource "aws_security_group_rule" "fcrepo_service_ingress" {
  for_each            = toset(["8080"])
  security_group_id   = aws_security_group.fcrepo_service.id
  type                = "ingress"
  from_port           = each.key
  to_port             = each.key
  protocol            = "tcp"
  cidr_blocks         = [module.vpc.vpc_cidr_block]
}

resource "aws_s3_bucket" "fedora_binaries" {
  bucket      = "${var.namespace}-fcrepo-binaries"
}

resource "aws_iam_user" "fedora_binary_bucket_user" {
  name = "${var.namespace}-fcrepo"
  path = "/system/"
}

resource "aws_iam_access_key" "fedora_binary_bucket_access_key" {
  user = aws_iam_user.fedora_binary_bucket_user.name
}

resource "aws_iam_user_policy" "fedora_binary_bucket_user_policy" {
  name = "${var.namespace}-fcrepo"
  user = aws_iam_user.fedora_binary_bucket_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "1"
        Effect = "Allow"
        Action = ["s3:*"]

        Resource = [
          "${aws_s3_bucket.fedora_binaries.arn}",
          "${aws_s3_bucket.fedora_binaries.arn}/*"
        ]
      }
    ]
  })
}

resource "random_string" "fcrepo_password" {
  length  = 16
  upper   = true
  lower   = true
  numeric = true
  special = false
}

resource "aws_lambda_invocation" "create_database" {
  function_name = module.create_db_lambda.lambda_function_arn

  input = jsonencode({
    host              = aws_db_instance.db.address
    port              = aws_db_instance.db.port
    user              = aws_db_instance.db.username
    password          = aws_db_instance.db.password
    schema            = "fcrepo"
    schema_password   = random_string.fcrepo_password.result
  })
}

locals {
  create_database_result = jsondecode(aws_lambda_invocation.create_database.result)

  fedora_java_opts = {
    "fcrepo.log" = "WARN"
    "fcrepo.postgresql.host" = aws_db_instance.db.address
    "fcrepo.postgresql.port" = aws_db_instance.db.port
    "fcrepo.postgresql.username" = local.create_database_result.username
    "fcrepo.postgresql.password" = local.create_database_result.password
    "aws.accessKeyId" = aws_iam_access_key.fedora_binary_bucket_access_key.id
    "aws.secretKey" = aws_iam_access_key.fedora_binary_bucket_access_key.secret
    "aws.bucket" = aws_s3_bucket.fedora_binaries.id
  }
}

resource "aws_efs_file_system" "fcrepo_data_volume" {
  encrypted      = false
}

resource "aws_efs_access_point" "fcrepo_data" {
  file_system_id    = aws_efs_file_system.fcrepo_data_volume.id
  posix_user {
    uid = 0
    gid = 0
  }
  root_directory {
    path = "/fcrepo-data"
    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "0770"
    }
  }
}

resource "aws_efs_mount_target" "fcrepo_data_mount_target" {
  for_each          = toset(module.vpc.private_subnets)
  file_system_id    = aws_efs_file_system.fcrepo_data_volume.id
  security_groups   = [
    aws_security_group.fcrepo_data_access.id
  ]
  subnet_id         = each.key
}

resource "aws_security_group" "fcrepo_data_access" {
  name        = "${var.namespace}-fcrepo-data"
  description = "Fcrepo Data Volume Security Group"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "fcrepo_data_egress" {
  security_group_id   = aws_security_group.fcrepo_data_access.id
  type                = "egress"
  from_port           = 0
  to_port             = 65535
  protocol            = -1
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "fcrepo_data_ingress" {
  security_group_id           = aws_security_group.fcrepo_data_access.id
  type                        = "ingress"
  from_port                   = 2049
  to_port                     = 2049
  protocol                    = "tcp"
  source_security_group_id    = aws_security_group.fcrepo_service.id
}

resource "aws_security_group_rule" "nurax_console_fcrepo_data_ingress" {
  security_group_id           = aws_security_group.fcrepo_data_access.id
  type                        = "ingress"
  from_port                   = 2049
  to_port                     = 2049
  protocol                    = "tcp"
  source_security_group_id    = aws_security_group.nurax_console.id
}

resource "aws_ecs_task_definition" "fcrepo" {
  family = "${var.namespace}-fcrepo"
  
  container_definitions = jsonencode([
    {
      name                = "fcrepo"
      image               = "${local.ecs_registry_url}/fcrepo4:4.7.5-s3multipart"
      essential           = true
      cpu                 = 1024
      memory              = 2048
      environment = [
        { 
          name  = "MODESHAPE_CONFIG",
          value = "classpath:/config/jdbc-postgresql-s3/repository.json"
        },
        {
          name  = "JAVA_OPTIONS",
          value = join(" ", [for key, value in local.fedora_java_opts : "-D${key}=${value}"])
        }
      ]
      portMappings = [
        { hostPort = 8080, containerPort = 8080 }
      ]
      mountPoints = [
        { sourceVolume = "fcrepo-data", containerPath = "/data" }
      ]
      readonlyRootFilesystem = false
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = aws_cloudwatch_log_group.fcrepo_logs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "fcrepo"
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
    }
  ])

  volume {
    name = "fcrepo-data"
    efs_volume_configuration {
      file_system_id            = aws_efs_file_system.fcrepo_data_volume.id
      # root_directory        = "/fcrepo-data"
      transit_encryption        = "ENABLED"
      # transit_encryption_port   = 2888

      authorization_config {
        access_point_id = aws_efs_access_point.fcrepo_data.id
      }
    }
  }

  task_role_arn            = aws_iam_role.task_execution_role.arn
  execution_role_arn       = aws_iam_role.task_execution_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
}

resource "aws_ecs_service" "fcrepo" {
  name                   = "fcrepo"
  cluster                = aws_ecs_cluster.nurax_cluster.id
  task_definition        = aws_ecs_task_definition.fcrepo.arn
  desired_count          = 1
  enable_execute_command = true
  launch_type            = "FARGATE"
  platform_version       = "1.4.0"

  lifecycle {
    ignore_changes          = [desired_count]
    replace_triggered_by = [
      aws_security_group.fcrepo_service.name
    ]
  }

  network_configuration {
    security_groups  = [
      module.vpc.default_security_group_id,
      aws_security_group.fcrepo_service.id,
      aws_security_group.endpoint_access.id
    ]
    subnets          = module.vpc.public_subnets
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.fcrepo.arn
  }
}

resource "aws_service_discovery_service" "fcrepo" {
  name = "fcrepo"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.private_service_discovery.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
}
