locals {
  service_account = merge({
    "create"   = true
    "metadata" = {}
  }, var.service_account)
}

resource "kubernetes_manifest" "service_account" {
  manifest = {
    "apiVersion" = "v1"
    "kind"       = "ServiceAccount"
    "metadata" = merge({
      "name"      = var.name
      "namespace" = var.namespace
    }, local.service_account["metadata"])
  }

  count = local.service_account["create"] ? 1 : 0
}
