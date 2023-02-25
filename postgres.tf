resource "random_string" "db_master_password" {
  length  = 16
  upper   = true
  lower   = true
  numeric = true
  special = false
}

resource "aws_security_group" "db" {
  name          = "${var.namespace}-db"
  description   = "RDS Security Group"
  vpc_id        = module.vpc.vpc_id
}

resource "aws_security_group_rule" "db_egress" {
  type                = "egress"
  security_group_id   = aws_security_group.db.id
  from_port           = 0
  to_port             = 65535
  protocol            = -1
  cidr_blocks         = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "db_ingress" {
  type                        = "ingress"
  security_group_id           = aws_security_group.db.id
  from_port                   = aws_db_instance.db.port
  to_port                     = aws_db_instance.db.port
  protocol                    = "tcp"
  source_security_group_id    = aws_security_group.db_client.id
}

resource "aws_security_group" "db_client" {
  name          = "${var.namespace}-db-client"
  description   = "RDS Client Security Group"
  vpc_id        = module.vpc.vpc_id
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name_prefix   = "${var.namespace}-db-"
  subnet_ids    = module.vpc.private_subnets

  lifecycle {
    create_before_destroy   = true
    ignore_changes          = [description]
  }
}

resource "aws_db_parameter_group" "db_parameter_group" {
  name_prefix   = "${var.namespace}-db-"
  family        = "postgres${element(split(".", var.postgres_version), 0)}"
  
  parameter {
    name = "client_encoding"
    value = "UTF8"
    apply_method = "pending-reboot"
  }

  parameter {
    name = "max_locks_per_transaction"
    value = 256
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "db" {
  allocated_storage         = 100
  apply_immediately         = true
  engine                    = "postgres"
  engine_version            = var.postgres_version
  instance_class            = var.db_instance_class
  db_name                   = var.namespace
  username                  = "dbadmin"
  parameter_group_name      = aws_db_parameter_group.db_parameter_group.name
  password                  = random_string.db_master_password.result
  maintenance_window        = "Mon:00:00-Mon:03:00"
  backup_window             = "03:00-06:00"
  backup_retention_period   = 35
  copy_tags_to_snapshot     = true
  db_subnet_group_name      = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids    = [aws_security_group.db.id]
}

module "create_db_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "4.10.1"

  function_name = "${var.namespace}-createdb"
  description   = "Create schemas in the ${aws_db_instance.db.db_name} database"
  handler       = "index.handler"
  runtime       = "nodejs16.x"
  timeout       = 10

  source_path   = "${path.module}/createdb"

  vpc_subnet_ids            = module.vpc.private_subnets
  vpc_security_group_ids    = [
    module.vpc.default_security_group_id, 
    aws_security_group.db_client.id
  ]
  attach_network_policy     = true
}