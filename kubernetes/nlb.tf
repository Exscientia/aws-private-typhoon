resource "aws_route53_record" "apiserver" {
  zone_id = var.dns_zone_id

  name = format("%s.%s.", var.cluster_name, var.dns_zone)
  type = "A"

  alias {
    name                   = aws_lb.nlb.dns_name
    zone_id                = aws_lb.nlb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_lb" "nlb" {
  name               = "${var.cluster_name}-nlb"
  load_balancer_type = "network"
  internal           = true

  subnets = module.vpc.private_subnets

  enable_cross_zone_load_balancing = true

  tags = merge(var.tags, {
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  })
}

resource "aws_lb_listener" "apiserver-https" {
  load_balancer_arn = aws_lb.nlb.arn
  protocol          = "TCP"
  port              = "6443"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.controllers.arn
  }
}

resource "aws_lb_target_group" "controllers" {
  name        = "${var.cluster_name}-controllers"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  protocol = "TCP"
  port     = 6443

  health_check {
    protocol = "TCP"
    port     = 6443

    healthy_threshold   = 3
    unhealthy_threshold = 3

    interval = 10
  }


  tags = merge(var.tags, {
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  })
}

resource "aws_lb_target_group_attachment" "controllers" {
  count = var.controller_count

  target_group_arn = aws_lb_target_group.controllers.arn
  target_id        = aws_instance.controllers.*.id[count.index]
  port             = 6443
}
