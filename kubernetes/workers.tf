module "workers" {
  source       = "./workers"
  name         = var.cluster_name
  cluster_name = var.cluster_name

  # AWS
  image_id                        = local.ami_id
  vpc_id                          = aws_vpc.network.id
  subnet_ids                      = aws_subnet.public.*.id
  security_groups                 = [aws_security_group.worker.id]
  worker_count                    = var.worker_count
  instance_type                   = var.worker_type
  disk_size                       = var.disk_size
  spot_price                      = var.worker_price
  target_groups                   = var.worker_target_groups
  worker_iam_instance_profile_arn = aws_iam_instance_profile.worker_node.arn

  # configuration
  kubeconfig            = module.bootstrap.kubeconfig-kubelet
  ssh_authorized_key    = var.ssh_authorized_key
  service_cidr          = var.service_cidr
  cluster_domain_suffix = var.cluster_domain_suffix
  clc_snippets          = var.worker_clc_snippets
  node_labels           = var.worker_node_labels

  tags = var.tags
}


resource "aws_iam_instance_profile" "worker_node" {
  name = "${var.cluster_name}-worker-node"
  role = aws_iam_role.worker_node.name
}

resource "aws_iam_role" "worker_node" {
  name                  = "${var.cluster_name}-worker-node"
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

resource "aws_iam_policy" "worker_node" {
  name = "${var.cluster_name}-worker-node"

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
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:BatchGetImage",
      "elasticfilesystem:*"
    ],
    "Resource": "*"
  }]
}
EOF
}

resource "aws_iam_role_policy_attachment" "worker_node" {
  role       = aws_iam_role.worker_node.name
  policy_arn = aws_iam_policy.worker_node.arn
}
