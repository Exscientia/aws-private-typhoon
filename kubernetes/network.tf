data "aws_availability_zones" "available" {
}

data "aws_security_group" "default" {
  name   = "default"
  vpc_id = module.vpc.vpc_id
}

locals {
  vpc_cidr     = "${var.cidr_prefix}.0.0.0/16"
  pod_cidr     = "${var.cidr_prefix}.2.0.0/16"
  service_cidr = "${var.cidr_prefix}.3.0.0/16"
  public_subnets = [
    for name, i in data.aws_availability_zones.available.names : "${var.cidr_prefix}.0.10${i}.0/24"
  ]
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.24.0"

  name                           = "${var.cluster_name}-vpc"
  cidr                           = local.vpc_cidr
  azs                            = data.aws_availability_zones.available.names
  private_subnets                = [local.pod_cidr, local.service_cidr]
  public_subnets                 = local.public_subnets
  enable_nat_gateway             = true
  single_nat_gateway             = true
  enable_dns_hostnames           = true
  enable_dns_support             = true
  enable_classiclink             = true
  enable_classiclink_dns_support = true
  enable_vpn_gateway             = true

  tags = merge(var.tags, {
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
  })

  public_subnet_tags = merge(var.tags, {
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
    "kubernetes.io/role/elb" : "1"
  })

  private_subnet_tags = merge(var.tags, {
    "kubernetes.io/cluster/${var.cluster_name}" : "shared"
    "kubernetes.io/role/internal-elb" : "1"
  })
}
