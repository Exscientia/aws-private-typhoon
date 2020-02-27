# Kubernetes assets (kubeconfig, manifests)
module "bootstrap" {
  source = "git::https://github.com/poseidon/terraform-render-bootstrap.git?ref=d1831e626a06d1aa63a75ca90a670ca594657fbf"

  cluster_name          = var.cluster_name
  cloud_provider        = "aws"
  api_servers           = [format("%s.%s", var.cluster_name, var.dns_zone)]
  etcd_servers          = aws_route53_record.etcds.*.fqdn
  asset_dir             = var.asset_dir
  networking            = "calico"
  network_mtu           = var.network_mtu
  pod_cidr              = local.pod_cidr
  service_cidr          = local.service_cidr
  cluster_domain_suffix = var.cluster_domain_suffix
  enable_reporting      = false
  enable_aggregation    = var.enable_aggregation
}
