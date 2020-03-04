locals {
  kubeconfig_path = "/kubeconfig"
}

resource "local_file" "kubeconfig" {
  sensitive_content = module.bootstrap.kubeconfig-admin
  filename          = local.kubeconfig_path
}

provider "kubernetes" {
  load_config_file = false
  config_path      = local.kubeconfig_path
}

resource "kubernetes_config_map" "testing" {
  metadata {
    name = "my-config"
  }

  data = {
    api_host = "myhost:443"
    db_host  = "dbhost:5432"
  }
}
