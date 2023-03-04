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

resource "aws_iam_policy" "allow_start_session" {
  name    = "${var.namespace}-allow-ssm-exec-command"
  policy  = data.aws_iam_policy_document.allow_start_session.json
}

resource "aws_iam_role_policy_attachment" "task_execution_role_policy" {
  role       = aws_iam_role.task_execution_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "task_allow_start_session" {
  role       = aws_iam_role.task_execution_role.id
  policy_arn = aws_iam_policy.allow_start_session.arn
}

data "aws_iam_policy_document" "deploy_nurax" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:TagResource",
      "ecr:UntagResource"
    ]
    resources = [
      aws_ecr_repository.nurax_images["nurax"].arn,
      "${aws_ecr_repository.nurax_images["nurax"].arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = ["ecs:UpdateService"]
    resources = ["${aws_ecs_cluster.nurax_cluster.arn}/*"]
  }
}

resource "aws_iam_policy" "deploy_nurax" {
  name    = "${var.namespace}-deploy"
  policy  = data.aws_iam_policy_document.deploy_nurax.json
}

resource "aws_iam_user" "deploy_nurax" {
  name    = "${var.namespace}-deploy"
}

resource "aws_iam_user_policy_attachment" "deploy_nurax" {
  user       = aws_iam_user.deploy_nurax.name
  policy_arn = aws_iam_policy.deploy_nurax.arn
}
