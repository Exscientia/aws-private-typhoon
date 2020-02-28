locals {
  ami_id         = data.aws_ami.flatcar.image_id
  bastion_ami_id = data.aws_ami.alpine.image_id
}

data "aws_ami" "flatcar" {
  most_recent = true
  owners      = ["075585003325"]

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "name"
    values = ["Flatcar-stable-*"]
  }
}

data "aws_ami" "alpine" {
  most_recent = true
  owners      = ["538276064493"]

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "name"
    values = ["alpine-ami-*"]
  }
}
