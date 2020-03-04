
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
  key_name      = aws_key_pair.bastion.key_name
  vpc_security_group_ids = [
    aws_security_group.bastion.id
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
  triggers = {
    public_ip = aws_instance.bastion.public_ip
  }
  depends_on = [
    aws_instance.bastion
  ]

  connection {
    private_key = tls_private_key.bastion.private_key_pem
    type        = "ssh"
    host        = aws_instance.bastion.public_ip
    user        = "alpine"
  }

  provisioner "remote-exec" {
    inline = [
      "echo -e '${tls_private_key.bastion.public_key_openssh}\n${join("\n", var.bastion_user_public_keys)}' > /home/alpine/.ssh/authorized_keys",
      "echo -e '${tls_private_key.bastion.private_key_pem}' > /home/alpine/.ssh/id_rsa",
      "chmod 600 /home/alpine/.ssh/id_rsa",
      "echo -e 'IdentityFile /home/alpine/.ssh/id_rsa' > /home/alpine/.ssh/config",
      "sudo sed -i 's/AllowTcpForwarding.*/AllowTcpForwarding yes/' /etc/ssh/sshd_config",
      "sudo /etc/init.d/sshd restart"
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

    cidr_blocks = var.bastion_whitelist
  }

  egress {
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    security_groups = [aws_security_group.controller.id]
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
