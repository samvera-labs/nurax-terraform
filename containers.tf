locals {
  repositories = toset(["fcrepo4", "fcrepo", "solr", "nurax"])
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
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
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

data "aws_iam_policy_document" "allow_ecr_pull" {
  statement {
    effect    = "Allow"
    actions   = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources  = ["*"]
  }
}

data "aws_iam_policy_document" "allow_efs_mount" {
  statement {
    effect    = "Allow"
    actions   = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:DescribeMountTargets",
      "elasticfilesystem:DescribeFileSystems"
    ]
    resources  = ["*"]
  }
}

data "aws_iam_policy_document" "allow_start_session" {
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

resource "aws_iam_policy" "allow_ecr_pull" {
  name    = "${var.namespace}-allow-ecr-pull"
  policy  = data.aws_iam_policy_document.allow_ecr_pull.json
}

resource "aws_iam_policy" "allow_efs_mount" {
  name    = "${var.namespace}-allow-efs-mount"
  policy  = data.aws_iam_policy_document.allow_efs_mount.json
}

resource "aws_iam_policy" "allow_start_session" {
  name    = "${var.namespace}-allow-ssm-exec-command"
  policy  = data.aws_iam_policy_document.allow_start_session.json
}

resource "aws_iam_role_policy_attachment" "task_execution_role_policy" {
  role       = aws_iam_role.task_execution_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "task_allow_ecr_pull" {
  role       = aws_iam_role.task_execution_role.id
  policy_arn = aws_iam_policy.allow_ecr_pull.arn
}

resource "aws_iam_role_policy_attachment" "task_allow_start_session" {
  role       = aws_iam_role.task_execution_role.id
  policy_arn = aws_iam_policy.allow_start_session.arn
}
