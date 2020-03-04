

resource "kubernetes_config_map" "testing" {
  metadata {
    name = "my-config"
  }

  data = {
    api_host = "myhost:443"
    db_host  = "dbhost:5432"
  }
}
