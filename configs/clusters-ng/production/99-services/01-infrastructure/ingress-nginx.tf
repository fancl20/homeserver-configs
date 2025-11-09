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

resource "google_dns_record_set" "ingress" {
  name = "local.${data.google_dns_managed_zone.default.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = data.google_dns_managed_zone.default.name

  rrdatas = [data.kubernetes_resource.ingress_service.object.status.loadBalancer.ingress[0].ip]
}

