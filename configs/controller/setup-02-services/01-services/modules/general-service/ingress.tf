locals {
  ingress = merge({
    "enabled"  = false
    "metadata" = {}
    "backend"  = {}
  }, var.ingress)
}

resource "kubernetes_manifest" "ingress" {
  manifest = {
    "apiVersion" = "networking.k8s.io/v1"
    "kind"       = "Ingress"
    "metadata" = merge({
      "name"      = var.name
      "namespace" = var.namespace
    }, local.ingress["metadata"])
    "spec" = {
      "tls" = [{ "hosts" = [local.hostname] }]
      "rules" = [{
        "host" = local.hostname
        "http" = {
          "paths" = [{
            "path"     = "/"
            "pathType" = "Prefix"
            "backend" = {
              "service" = {
                "name" = lookup(local.ingress["backend"], "service", var.name)
                "port" = { "number" = lookup(local.ingress["backend"], "port", 80) }
              }
            }
          }]
        }
      }]
    }
  }

  count = local.ingress["enabled"] ? 1 : 0
}
