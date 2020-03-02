
resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  key_name   = "bastion"
  public_key = tls_private_key.bastion.public_key_openssh
}

resource "aws_instance" "bastion" {
  ami           = local.bastion_ami_id
  instance_type = "t3.small"
  #   user_data     = data.ct_config.controller-ignitions.*.rendered[count.index]
  key_name = aws_key_pair.bastion.key_name
  vpc_security_group_ids = [
    aws_security_group.bastion.id,
    aws_security_group.controller.id
  ]

  associate_public_ip_address = true
  subnet_id                   = module.vpc.public_subnets[0]

  iam_instance_profile = aws_iam_instance_profile.bastion.name

  tags = merge(var.tags, {
    Name : "${var.cluster_name}-bastion"
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  })

  volume_tags = merge(var.tags, {
    Name = "${var.cluster_name}-bastion"
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  })

  lifecycle {
    ignore_changes = [
      ami,
      user_data,
    ]
  }
}

resource "null_resource" "copy-bastion-secrets" {
  depends_on = [
    aws_instance.bastion,
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.bastion.public_ip
    user        = "alpine"
    private_key = tls_private_key.bastion.private_key_pem
    timeout     = "15m"
  }

  provisioner "file" {
    content     = join("\n", var.bastion_user_public_keys)
    destination = "/authorized_keys"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /authorized_keys /root/.ssh/authorized_keys",
      "sudo chmod 644 /root/.ssh/authorized_keys",
    ]
  }
}

resource "aws_security_group" "bastion" {
  name        = "${var.cluster_name}-bastion"
  vpc_id      = module.vpc.vpc_id
  description = "Bastion security group (only SSH inbound access is allowed)"

  ingress {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22

    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = -1
    security_groups = [aws_security_group.controller.id]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-bastion"
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  })

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_iam_instance_profile" "bastion" {
  name = "${var.cluster_name}-bastion"
  role = aws_iam_role.bastion.name
}

resource "aws_iam_role" "bastion" {
  name               = "${var.cluster_name}-bastion"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.bastion.json
}

data "aws_iam_policy_document" "bastion" {
  statement {
    sid = ""

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    effect = "Allow"
  }
}
