resource "random_password" "coder_db" {
  length = 32
  special = false
}

resource "kubernetes_secret" "coder" {
  metadata {
    name      = "coder-db"
    namespace = "coder"
  }
  data = {
    POSTGRES_USER = "coder"
    POSTGRES_PASSWORD = random_password.unifi_db.result
    url = "postgres://coder:${random_password.unifi_db.result}@coder-db.coder.svc.cluster.local:5432/coder?sslmode=disable"
  }
}

data "google_dns_managed_zone" "default" {
  name        = "default"
}

data "kubernetes_resource" "ingress_service" {
  api_version = "v1"
  kind        = "Service"

  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
}

resource "google_dns_record_set" "coder" {
  name = "coder.local.${data.google_dns_managed_zone.default.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = data.google_dns_managed_zone.default.name

  rrdatas = [data.kubernetes_resource.ingress_service.object.status.loadBalancer.ingress[0].ip]
}

