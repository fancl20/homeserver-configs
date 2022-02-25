locals {
  deployment = merge({
    "volumes" = null # ... similar to annotations we can't use [] here
  }, var.deployment)
  podAnnotations = merge(
    module.vault_injector.annotations,
    lookup(local.deployment, "podAnnotations", {})
  )
}

resource "kubernetes_manifest" "deployment" {
  manifest = {
    "apiVersion" = "apps/v1"
    "kind"       = "Deployment"
    "metadata" = {
      "name"      = var.name
      "namespace" = var.namespace
    }
    "spec" = {
      "replicas" = 1
      "strategy" = {
        "rollingUpdate" = {
          "maxSurge"       = 0
          "maxUnavailable" = "100%"
        }
      }
      "selector" = {
        "matchLabels" = local.selector_labels
      }
      "template" = {
        "metadata" = {
          # https://github.com/hashicorp/terraform-provider-kubernetes/issues/1388
          "annotations" = length(local.podAnnotations) == 0 ? null : local.podAnnotations
          "labels" = {
            "app.kubernetes.io/name" = var.name
          }
        }
        "spec" = {
          "serviceAccountName" = local.service_account["create"] ? var.name : "default"
          "containers"         = [for c in local.deployment["containers"] : merge({ "name" = var.name }, c)]
          "volumes"            = local.deployment["volumes"]
        }
      }
    }
  }
}
