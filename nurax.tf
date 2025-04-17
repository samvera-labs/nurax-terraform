data "aws_iam_policy_document" "nurax_role_permissions" {
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

resource "aws_security_group" "nurax" {
  name    = var.namespace
  vpc_id  = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description       = "HTTP in"
    from_port         = 3000
    to_port           = 3000
    protocol          = "tcp"
    security_groups   = [aws_security_group.nurax_load_balancer.id]
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

resource "aws_iam_role_policy_attachment" "nurax_allow_start_session" {
  role       = aws_iam_role.nurax_role.id
  policy_arn = aws_iam_policy.allow_start_session.arn
}

resource "aws_iam_role_policy_attachment" "nurax_allow_efs_mount" {
  role       = aws_iam_role.nurax_role.id
  policy_arn = aws_iam_policy.allow_efs_mount.arn
}

resource "aws_iam_role_policy_attachment" "nurax_ecs_launch_task" {
  role       = aws_iam_role.nurax_role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_efs_file_system" "nurax_data_volume" {
  encrypted      = false
}

resource "aws_efs_mount_target" "nurax_data_mount_target" {
  for_each          = toset(module.vpc.private_subnets)
  file_system_id    = aws_efs_file_system.nurax_data_volume.id
  security_groups   = [
    aws_security_group.nurax_data_access.id
  ]
  subnet_id         = each.key
}

resource "aws_security_group" "nurax_data_access" {
  name        = "${var.namespace}-app-data"
  description = "Nurax Application Data Volume Security Group"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "nurax_data_egress" {
  security_group_id   = aws_security_group.nurax_data_access.id
  type                = "egress"
  from_port           = 0
  to_port             = 65535
  protocol            = -1
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "nurax_data_ingress" {
  security_group_id           = aws_security_group.nurax_data_access.id
  type                        = "ingress"
  from_port                   = 2049
  to_port                     = 2049
  protocol                    = "tcp"
  source_security_group_id    = aws_security_group.nurax.id
}

resource "aws_security_group_rule" "nurax_console_app_data_ingress" {
  security_group_id           = aws_security_group.nurax_data_access.id
  type                        = "ingress"
  from_port                   = 2049
  to_port                     = 2049
  protocol                    = "tcp"
  source_security_group_id    = aws_security_group.nurax_console.id
}
