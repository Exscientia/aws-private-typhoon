resource "aws_autoscaling_group" "workers" {
  count = length(var.subnet_ids)
  name  = "${var.name}-${count.index}-worker ${aws_launch_template.worker.name}"

  desired_capacity          = var.min_workers
  min_size                  = var.min_workers
  max_size                  = var.max_workers
  default_cooldown          = 30
  health_check_grace_period = 30

  vpc_zone_identifier = [var.subnet_ids[count.index]]

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  target_group_arns = flatten([
    var.target_groups,
  ])

  lifecycle {
    # override the default destroy and replace update behavior
    create_before_destroy = true
  }

  # Waiting for instance creation delays adding the ASG to state. If instances
  # can't be created (e.g. spot price too low), the ASG will be orphaned.
  # Orphaned ASGs escape cleanup, can't be updated, and keep bidding if spot is
  # used. Disable wait to avoid issues and align with other clouds.
  wait_for_capacity_timeout = "0"

  tags = [
    {
      key                 = "Name"
      value               = "${var.name}-${count.index}-worker"
      propagate_at_launch = true
      }, {
      key                 = "k8s.io/cluster-autoscaler/enabled"
      value               = "true"
      propagate_at_launch = true
      }, {
      key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
      value               = "shared"
      propagate_at_launch = true
      }, {
      key                 = "kubernetes.io/cluster/${var.cluster_name}"
      value               = "shared"
      propagate_at_launch = true
    }
  ]
}

resource "aws_launch_template" "worker" {
  ebs_optimized = true
  image_id      = var.image_id
  instance_type = var.instance_type
  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price = var.spot_price
    }
  }
  monitoring {
    enabled = false
  }
  user_data = base64encode(data.ct_config.worker-ignition.rendered)

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type = var.disk_type
      volume_size = var.disk_size
      iops        = var.disk_iops
      encrypted   = true
    }
  }

  vpc_security_group_ids = var.security_groups

  iam_instance_profile {
    arn = var.worker_iam_instance_profile_arn
  }

  tag_specifications {
    resource_type = "instance"
    tags          = var.tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = var.tags
  }

  lifecycle {
    // Override the default destroy and replace update behavior
    create_before_destroy = true
    ignore_changes        = [image_id]
  }

  tags = merge(var.tags, {
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  })
}

data "ct_config" "worker-ignition" {
  content      = data.template_file.worker-config.rendered
  pretty_print = false
  snippets     = var.clc_snippets
  platform     = "ec2"
}

data "template_file" "worker-config" {
  template = file("${path.module}/cl/worker.yaml")

  vars = {
    kubeconfig             = indent(10, var.kubeconfig)
    ssh_authorized_key     = var.ssh_authorized_key
    cluster_dns_service_ip = cidrhost(var.service_cidr, 10)
    cluster_domain_suffix  = var.cluster_domain_suffix
    cgroup_driver          = "cgroupfs"
    node_labels            = join(",", var.node_labels)
  }
}
