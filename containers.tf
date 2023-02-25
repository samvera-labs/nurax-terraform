locals {
  repositories = toset(["fcrepo4", "solr", "nurax"])
}

locals {
  ecs_registry_url = format("%s.dkr.ecr.%s.amazonaws.com", data.aws_caller_identity.current.id, data.aws_region.current.name)
}

resource "aws_ecs_cluster" "nurax_cluster" {
  name = var.namespace
}

resource "aws_ecr_repository" "nurax_images" {
  for_each                = local.repositories
  name                    = each.key
  image_tag_mutability    = "MUTABLE"
}

resource "aws_ecr_lifecycle_policy" "nurax_image_expiration" {
  for_each    = local.repositories
  repository  = aws_ecr_repository.nurax_images[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type        = "expire"
        }
      }
    ]
  })
}

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "task_execution_role" {
  name                  = "ecsTaskExecutionRole"
  managed_policy_arns   = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]

  assume_role_policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      {
        Sid = ""
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

data "aws_iam_policy_document" "ecs_exec_command" {
  statement {
    effect    = "Allow"
    actions   = [
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:CreateControlChannel"
    ]
    resources  = ["*"]
  }
}

resource "aws_iam_policy" "ecs_exec_command" {
  name    = "${var.namespace}-allow-ecs-exec"
  policy  = data.aws_iam_policy_document.ecs_exec_command.json
}
