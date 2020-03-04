# Discrete DNS records for each controller's private IPv4 for etcd usage
resource "aws_route53_record" "etcds" {
  count = var.controller_count

  # DNS Zone where record should be created
  zone_id = var.dns_zone_id

  name = format("%s-etcd%d.%s.", var.cluster_name, count.index, var.dns_zone)
  type = "A"
  ttl  = 300

  # private IPv4 address for etcd
  records = [aws_instance.controllers.*.private_ip[count.index]]
}

# Controller instances
resource "aws_instance" "controllers" {
  count = var.controller_count

  ami           = local.ami_id
  ebs_optimized = true
  instance_type = var.controller_type
  user_data     = data.ct_config.controller-ignitions.*.rendered[count.index]

  # storage
  root_block_device {
    volume_type = var.disk_type
    volume_size = var.disk_size
    iops        = var.disk_iops
    encrypted   = true
  }

  # network
  associate_public_ip_address = false
  subnet_id                   = element(module.vpc.public_subnets, count.index)
  vpc_security_group_ids      = [aws_security_group.controller.id]

  iam_instance_profile = aws_iam_instance_profile.controller_node.name

  tags = merge(var.tags, {
    Name : "${var.cluster_name}-controller-${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  })

  volume_tags = merge(var.tags, {
    Name = "${var.cluster_name}-controller-${count.index}"
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  })

  lifecycle {
    ignore_changes = [
      ami,
      user_data,
    ]
  }

  depends_on = [
    aws_lb.nlb
  ]
}

resource "aws_iam_instance_profile" "controller_node" {
  name = "${var.cluster_name}-controller-node"
  role = aws_iam_role.controller_node.name
}

resource "aws_iam_role" "controller_node" {
  name                  = "${var.cluster_name}-controller-node"
  force_detach_policies = true
  assume_role_policy    = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = merge(var.tags, {
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  })
}

resource "aws_iam_policy" "controller_node" {
  name = "${var.cluster_name}-controller-node"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVolumes",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyVolume",
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteVolume",
      "ec2:DetachVolume",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DescribeVpcs",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:AttachLoadBalancerToSubnets",
      "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateLoadBalancerPolicy",
      "elasticloadbalancing:CreateLoadBalancerListeners",
      "elasticloadbalancing:ConfigureHealthCheck",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancerListeners",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DetachLoadBalancerFromSubnets",
      "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
      "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancerPolicies",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
      "iam:CreateServiceLinkedRole",
      "kms:DescribeKey",
      "elasticfilesystem:*"
    ],
    "Resource": [
      "*"
    ]
  }]
}
EOF
}

resource "aws_iam_role_policy_attachment" "controller_node" {
  role       = aws_iam_role.controller_node.name
  policy_arn = aws_iam_policy.controller_node.arn
}

# Controller Ignition configs
data "ct_config" "controller-ignitions" {
  count        = var.controller_count
  content      = data.template_file.controller-configs.*.rendered[count.index]
  pretty_print = false
  snippets     = var.controller_clc_snippets
  platform     = "ec2"
}

# Controller Container Linux configs
data "template_file" "controller-configs" {
  count = var.controller_count

  template = file("${path.module}/cl/controller.yaml")

  vars = {
    # Cannot use cyclic dependencies on controllers or their DNS records
    etcd_name   = "etcd${count.index}"
    etcd_domain = format("%s-etcd%d.%s", var.cluster_name, count.index, var.dns_zone)
    # etcd0=https://cluster-etcd0.example.com,etcd1=https://cluster-etcd1.example.com,...
    etcd_initial_cluster = join(",", data.template_file.etcds.*.rendered)
    cgroup_driver        = "cgroupfs"
    kubeconfig           = indent(10, module.bootstrap.kubeconfig-kubelet)
    # ssh_authorized_key     = var.ssh_authorized_key
    ssh_authorized_key     = tls_private_key.bastion.public_key_openssh
    cluster_dns_service_ip = cidrhost(local.service_cidr, 10)
    cluster_domain_suffix  = var.cluster_domain_suffix
  }
}

data "template_file" "etcds" {
  count    = var.controller_count
  template = "etcd$${index}=https://$${cluster_name}-etcd$${index}.$${dns_zone}:2380"

  vars = {
    index        = count.index
    cluster_name = var.cluster_name
    dns_zone     = var.dns_zone
  }
}
