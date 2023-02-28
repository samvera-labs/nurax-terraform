data "aws_iam_policy_document" "nurax_role_permissions" {
  statement {
    sid       = "configuration"
    effect    = "Allow"
    actions   = [ "secretsmanager:Get*" ]
    resources = ["arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.id}:secret:config/nurax-*"]
  }

  statement {
    sid = "email"
    effect = "Allow"
    actions = [
      "ses:Send*"
    ]
    resources = ["*"]
  }
}

resource "aws_security_group" "nurax_load_balancer" {
  name          = "${var.namespace}-lb"
  description   = "Nurax Load Balancer Security Group"
  vpc_id        = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description   = "HTTP in"
    from_port     = 80
    to_port       = 80
    protocol      = "tcp"
    cidr_blocks   = ["0.0.0.0/0"]
  }

  ingress {
    description   = "HTTPS in"
    from_port     = 443
    to_port       = 443
    protocol      = "tcp"
    cidr_blocks   = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "nurax_role" {
  name               = "${var.namespace}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json
}

resource "aws_iam_policy" "nurax_role_policy" {
  name   = "${var.namespace}-policy"
  policy = data.aws_iam_policy_document.nurax_role_permissions.json
}

resource "aws_iam_role_policy_attachment" "nurax_role_policy" {
  role       = aws_iam_role.nurax_role.id
  policy_arn = aws_iam_policy.nurax_role_policy.arn
}

resource "aws_iam_role_policy_attachment" "nurax_ecs_exec_command" {
  role       = aws_iam_role.nurax_role.id
  policy_arn = aws_iam_policy.ecs_exec_command.arn
}
