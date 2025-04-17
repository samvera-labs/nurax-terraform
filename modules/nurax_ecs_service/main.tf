resource "aws_cloudwatch_log_group" "this_logs" {
  name = "/ecs/${var.namespace}"
  retention_in_days   = 3
}

resource "aws_lb_target_group" "this_target" {
  port                    = 3000
  deregistration_delay    = 30
  target_type             = "ip"
  protocol                = "HTTP"
  vpc_id                  = var.vpc_id

  health_check {
    path = "/"
    interval = 60
    healthy_threshold = 2
    unhealthy_threshold = 10
  }

  stickiness {
    enabled = false
    type    = "lb_cookie"
  }
}

resource "aws_lb" "this_load_balancer" {
  name               = "${var.namespace}-lb"
  internal           = false
  load_balancer_type = "application"

  subnets         = var.public_subnets
  security_groups = [var.lb_security_group_id]
  idle_timeout = 300
}

resource "aws_lb_listener" "this_lb_listener_http" {
  load_balancer_arn = aws_lb.this_load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

}

resource "aws_lb_listener" "this_lb_listener_https" {
  load_balancer_arn = aws_lb.this_load_balancer.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this_target.arn
  }

}

resource "random_id" "secret_key_base" {
  byte_length = 64
}
