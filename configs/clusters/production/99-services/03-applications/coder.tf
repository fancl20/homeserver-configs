resource "random_password" "coder_db" {
  length = 32
  special = false
}

resource "kubernetes_secret_v1" "coder" {
  metadata {
    name      = "coder-db"
    namespace = "coder"
  }
  data = {
    POSTGRES_USER = "coder"
    POSTGRES_PASSWORD = random_password.coder_db.result
    url = "postgres://coder:${random_password.coder_db.result}@coder-db.coder.svc.cluster.local:5432/coder?sslmode=disable"
  }
}

data "google_dns_managed_zone" "default" {
  name        = "default"
}

data "kubernetes_resource" "gateway" {
  api_version = "gateway.networking.k8s.io/v1"
  kind        = "Gateway"
  metadata {
    name      = "default"
    namespace = "nginx-gateway"
  }
}

resource "google_dns_record_set" "coder" {
  name = "coder.local.${data.google_dns_managed_zone.default.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = data.google_dns_managed_zone.default.name

  rrdatas = [data.kubernetes_resource.gateway.object.status.addresses[0].value]
}

