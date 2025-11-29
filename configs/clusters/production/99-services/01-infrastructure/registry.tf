data "google_dns_managed_zone" "default" {
  name = "default"
}

data "kubernetes_resource" "gateway" {
  api_version = "gateway.networking.k8s.io/v1"
  kind        = "Gateway"
  metadata {
    name      = "default"
    namespace = "nginx-gateway"
  }
}

resource "google_dns_record_set" "registry" {
  name = "registry.local.${data.google_dns_managed_zone.default.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = data.google_dns_managed_zone.default.name

  rrdatas = [data.kubernetes_resource.gateway.object.status.addresses[0].value]
}

