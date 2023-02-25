resource "aws_security_group" "samvera_stack_service" {
  name        = "${var.namespace}-solr-service"
  description = "Fedora/Solr Service Security Group"
  vpc_id      = module.vpc.vpc_id
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
  for_each            = toset(["8080", "8983", "9983"])
  security_group_id   = aws_security_group.samvera_stack_service.id
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
    "fcrepo.postgresql.host" = aws_db_instance.db.address
    "fcrepo.postgresql.port" = aws_db_instance.db.port
    "fcrepo.postgresql.username" = local.create_database_result.username
    "fcrepo.postgresql.password" = local.create_database_result.password
    "aws.accessKeyId" = aws_iam_access_key.fedora_binary_bucket_access_key.id
    "aws.secretKey" = aws_iam_access_key.fedora_binary_bucket_access_key.secret
    "aws.bucket" = aws_s3_bucket.fedora_binaries.id
  }
}

resource "aws_efs_file_system" "solr_backup_volume" {
  encrypted      = false
}

resource "aws_efs_mount_target" "solr_backup_mount_target" {
  for_each          = toset(module.vpc.private_subnets)
  file_system_id    = aws_efs_file_system.solr_backup_volume.id
  security_groups   = [
    aws_security_group.solr_backup_access.id
  ]
  subnet_id         = each.key
}

resource "aws_security_group" "solr_backup_access" {
  name        = "${var.namespace}-solr-backup"
  description = "Solr Backup Volume Security Group"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "solr_backup_egress" {
  security_group_id   = aws_security_group.solr_backup_access.id
  type                = "egress"
  from_port           = 0
  to_port             = 65535
  protocol            = -1
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "solr_backup_ingress" {
  security_group_id           = aws_security_group.solr_backup_access.id
  type                        = "ingress"
  from_port                   = 2049
  to_port                     = 2049
  protocol                    = "tcp"
  source_security_group_id    = aws_security_group.samvera_stack_service.id
}

resource "aws_ecs_task_definition" "samvera_stack" {
  family = "${var.namespace}-samvera-stack"
  
  container_definitions = jsonencode([
    {
      name                = "fcrepo"
      image               = "${local.ecs_registry_url}/fcrepo4:4.7.5-s3multipart"
      essential           = true
      cpu                 = var.fcrepo_cpu
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
      readonlyRootFilesystem = false
      healthCheck = {
        command  = ["CMD-SHELL", "wget -q -O /dev/null --method=OPTIONS http://localhost:8080/rest/"]
        interval = 30
        retries  = 3
        timeout  = 5
      }
    },
    {
      name                = "solrcloud",
      image               = "${local.ecs_registry_url}/solr:8.11-slim"
      essential           = true
      cpu                 = var.solrcloud_cpu
      command             = ["solr", "-f", "-cloud"]
      environment = [
        { name = "KAFKA_OPTS",      value = "-Dzookeeper.4lw.commands.whitelist=*" },
        { name = "SOLR_HEAP",       value = "${var.solrcloud_cpu * 0.9765625}m" }
      ]
      portMappings = [
        { hostPort = 8983, containerPort = 8983 },
        { hostPort = 9983, containerPort = 9983 }
      ]
      mountPoints = [
        { sourceVolume = "solr-backup", containerPath = "/data/backup" }
      ]
      readonlyRootFilesystem = false
      healthCheck = {
        command  = ["CMD-SHELL", "wget -q -O /dev/null http://localhost:8983/solr/"]
        interval = 30
        retries  = 3
        timeout  = 5
      }
    }
  ])

  volume {
    name = "fcrepo-data"
  }

  volume {
    name = "solr-backup"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.solr_backup_volume.id
    }
  }

  task_role_arn            = aws_iam_role.task_execution_role.arn
  execution_role_arn       = aws_iam_role.task_execution_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fcrepo_cpu + var.solrcloud_cpu
  memory                   = var.samvera_stack_memory
}

resource "aws_ecs_service" "samvera_stack" {
  name                   = "samvera-stack"
  cluster                = aws_ecs_cluster.nurax_cluster.id
  task_definition        = aws_ecs_task_definition.samvera_stack.arn
  desired_count          = 0
  enable_execute_command = true
  launch_type            = "FARGATE"
  platform_version       = "1.4.0"

  lifecycle {
    ignore_changes          = [desired_count]
  }

  network_configuration {
    security_groups  = [aws_security_group.samvera_stack_service.id]
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
