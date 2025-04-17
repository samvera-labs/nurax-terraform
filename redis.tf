resource "aws_security_group" "redis_service" {
  name   = "${var.namespace}-redis-service"
  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group_rule" "redis_egress" {
  security_group_id = aws_security_group.redis_service.id
  type              = "egress"
  from_port         = "0"
  to_port           = "0"
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "redis_ingress" {
  security_group_id   = aws_security_group.redis_service.id
  type                = "ingress"
  from_port           = "6379"
  to_port             = "6379"
  protocol            = "tcp"
  cidr_blocks         = [module.vpc.vpc_cidr_block]
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.namespace}-redis"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_elasticache_cluster" "redis" {
  for_each             = toset(["dev", "pg", "f6"])
  cluster_id           = "${var.namespace}-${each.key}-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  engine_version       = "7.1"
  security_group_ids   = [aws_security_group.redis_service.id]
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
}
