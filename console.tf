locals {
  console_services = ["cloudwatch", "ec2", "ecr", "ecs", "efs", "iam", "lambda", "rds", "route53", "servicediscovery", "vpc"]
}

data "aws_iam_policy_document" "nurax_console" {
  statement {
    effect = "Allow"
    actions = [
      "s3:*",
    ]
    resources = [
      "${aws_s3_bucket.fedora_binaries.arn}",
      "${aws_s3_bucket.fedora_binaries.arn}/*"
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = [ "*" ]
  }

  statement {
    effect    = "Allow"
    actions   = [for service in local.console_services: "${service}:*"]
    resources = [ "*" ]

    # condition {
    #   test        = "StringEquals"
    #   variable    = "aws:ResourceTag/Namespace"
    #   values      = [var.namespace]
    # }
  }
}

resource "aws_iam_policy" "nurax_console_policy" {
  name    = "${var.namespace}-console"
  policy  = data.aws_iam_policy_document.nurax_console.json
}

resource "aws_iam_role" "nurax_console_role" {
  name = "${var.namespace}-console"

  assume_role_policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      {
        Sid = ""
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "nurax_console_task_policy" {
  role       = aws_iam_role.nurax_console_role.id
  policy_arn = aws_iam_policy.nurax_role_policy.arn
}

resource "aws_iam_role_policy_attachment" "nurax_console_admin_policy" {
  role       = aws_iam_role.nurax_console_role.id
  policy_arn = aws_iam_policy.nurax_console_policy.arn
}

resource "aws_iam_instance_profile" "console_instance_profile" {
  name = "${var.namespace}-console-profile"
  role    = aws_iam_role.nurax_console_role.name
}

resource "aws_security_group" "nurax_console" {
  name    = "${var.namespace}-console"
  vpc_id  = module.vpc.vpc_id
}

data "aws_ami" "nurax_console" {
  owners        = [136693071363]
  most_recent   = true

  filter {
    name   = "name"
    values = ["debian-12-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "random_shuffle" "az" {
  input           = module.vpc.public_subnets
  result_count    = 1
}

data "aws_subnet" "nurax_console_subnet" {
  id = random_shuffle.az.result[0]
}

resource "aws_instance" "nurax_console" {
  ami             = data.aws_ami.nurax_console.id
  instance_type   = "t3a.small"
  key_name        = "nurax"

  disable_api_termination                 = true
  instance_initiated_shutdown_behavior    = "stop"

  availability_zone             = data.aws_subnet.nurax_console_subnet.availability_zone
  subnet_id                     = data.aws_subnet.nurax_console_subnet.id
  iam_instance_profile          = aws_iam_instance_profile.console_instance_profile.name

  associate_public_ip_address   = true

  vpc_security_group_ids = [
    module.vpc.default_security_group_id,
    aws_security_group.nurax_console.id,
    aws_security_group.nurax.id,
    aws_security_group.ssh.id,
  ]

  ebs_block_device {
    device_name             = "/dev/xvda"
    encrypted               = false
    delete_on_termination   = true
    volume_size             = 50
    volume_type             = "gp3"
    throughput              = 125
  }

  user_data = templatefile(
    "${path.module}/support/console-init.sh", 
    { 
      console_users = join(" ", var.console_users)
      stack_efs_id  = aws_efs_file_system.samvera_stack_data_volume.id
      nurax_efs_id  = aws_efs_file_system.nurax_data_volume.id
    }
  )

  lifecycle {
    ignore_changes = [ user_data, associate_public_ip_address ]
  }
  tags = {
    Name = "${var.namespace}-console"
  }
}