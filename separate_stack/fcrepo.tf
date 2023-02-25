resource "random_string" "fcrepo_password" {
  length  = 16
  upper   = true
  lower   = true
  numeric = true
  special = false
}

locals {
  create_database_result = jsondecode(aws_lambda_invocation.create_database.result)

  java_opts = {
    "fcrepo.postgresql.host" = aws_db_instance.db.address
    "fcrepo.postgresql.port" = aws_db_instance.db.port
    "fcrepo.postgresql.username" = local.create_database_result.username
    "fcrepo.postgresql.password" = local.create_database_result.password
    "aws.accessKeyId" = aws_iam_access_key.fedora_binary_bucket_access_key.id
    "aws.secretKey" = aws_iam_access_key.fedora_binary_bucket_access_key.secret
    "aws.bucket" = aws_s3_bucket.fedora_binary_bucket.id
  }
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

resource "aws_ecs_cluster" "fcrepo" {
  name = "fcrepo"
}

resource "aws_cloudwatch_log_group" "fcrepo_logs" {
  name                = "/ecs/fcrepo"
  retention_in_days   = 3
}

resource "aws_s3_bucket" "fedora_binary_bucket" {
  bucket = "${var.namespace}-fedora-binaries"
}

resource "aws_s3_bucket_lifecycle_configuration" "fedora_binary_bucket" {
  bucket = aws_s3_bucket.fedora_binary_bucket.bucket
  rule {
    id        = "purge-deleted-objects"
    status    = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 2
    }

    expiration {
      days = 0
      expired_object_delete_marker = true
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }    
  }
}

resource "aws_iam_user" "fedora_binary_bucket_user" {
  name = "${var.namespace}-fcrepo"
  path = "/system/"
}

resource "aws_iam_access_key" "fedora_binary_bucket_access_key" {
  user = aws_iam_user.fedora_binary_bucket_user.name
}

data "aws_iam_policy_document" "fedora_binary_bucket_access" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["arn:aws:s3:::*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [aws_s3_bucket.fedora_binary_bucket.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]

    resources = ["${aws_s3_bucket.fedora_binary_bucket.arn}/*"]
  }
}

resource "aws_iam_policy" "fedora_binary_bucket_policy" {
  name   = "${var.namespace}-fcrepo-s3-bucket-access"
  policy = data.aws_iam_policy_document.fedora_binary_bucket_access.json
}

resource "aws_iam_user_policy_attachment" "fedora_binary_bucket_user_access" {
  user       = aws_iam_user.fedora_binary_bucket_user.name
  policy_arn = aws_iam_policy.fedora_binary_bucket_policy.arn
}

resource "aws_security_group" "fcrepo_service" {
  name        = "${var.namespace}-fcrepo-service"
  description = "Fedora Repository Service Security Group"
  vpc_id      = module.vpc.vpc_id

}

resource "aws_security_group_rule" "fcrepo_service_egress" {
  security_group_id   = aws_security_group.fcrepo_service.id
  type                = "egress"
  from_port           = 0
  to_port             = 65535
  protocol            = "tcp"
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "fcrepo_service_ingress" {
  security_group_id   = aws_security_group.fcrepo_service.id
  type                = "ingress"
  from_port           = 8080
  to_port             = 8080
  protocol            = "tcp"
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group" "fcrepo_client" {
  name        = "${var.namespace}-fcrepo-client"
  description = "Fedora Repository Client Security Group"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_iam_role" "fcrepo_task_role" {
  name               = "fcrepo"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_role_policy_attachment" "fcrepo_binary_bucket_access" {
  role       = aws_iam_role.fcrepo_task_role.id
  policy_arn = aws_iam_policy.fedora_binary_bucket_policy.arn
}

resource "aws_iam_role_policy_attachment" "fcrepo_exec_command" {
  role       = aws_iam_role.fcrepo_task_role.id
  policy_arn = aws_iam_policy.ecs_exec_command.arn
}

resource "aws_ecs_task_definition" "fcrepo" {
  family = "fcrepo"
  container_definitions = jsonencode([
    {
      name                = "fcrepo"
      image               = "${local.ecs_registry_url}/fcrepo4:4.7.5-s3multipart"
      essential           = true
      cpu                 = var.fcrepo_cpu
      memoryReservation   = var.fcrepo_memory
      environment = [
        { 
          name  = "MODESHAPE_CONFIG",
          value = "classpath:/config/jdbc-postgresql-s3/repository.json"
        },
        {
          name  = "JAVA_OPTIONS",
          value = join(" ", [for key, value in local.java_opts : "-D${key}=${value}"])
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
      healthCheck = {
        command  = ["CMD-SHELL", "wget -q -O /dev/null --method=OPTIONS http://localhost:8080/rest/"]
        interval = 30
        retries  = 3
        timeout  = 5
      }
    }
  ])

  volume {
    name = "fcrepo-data"
  }

  task_role_arn            = aws_iam_role.fcrepo_task_role.arn
  execution_role_arn       = aws_iam_role.task_execution_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fcrepo_cpu
  memory                   = var.fcrepo_memory
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

resource "aws_ecs_service" "fcrepo" {
  name                   = "fcrepo"
  cluster                = aws_ecs_cluster.fcrepo.id
  task_definition        = aws_ecs_task_definition.fcrepo.arn
  desired_count          = 1
  enable_execute_command = true
  launch_type            = "FARGATE"
  platform_version       = "1.4.0"
  
  lifecycle {
    ignore_changes          = [desired_count]
  }

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [ 
      aws_security_group.fcrepo_service.id,
      aws_security_group.db_client.id
    ]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.fcrepo.arn
  }

}
