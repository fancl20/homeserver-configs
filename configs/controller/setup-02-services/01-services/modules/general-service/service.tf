resource "kubernetes_manifest" "service" {
  manifest = {
    "apiVersion" = "v1"
    "kind"       = "Service"
    "metadata" = {
      "name"        = each.key
      "namespace"   = var.namespace
      "annotations" = lookup(each.value, "externalDNS", false) ? { "external-dns.alpha.kubernetes.io/hostname" = local.hostname } : null
    },
    "spec" = merge(
      { "type" = "ClusterIP", "selector" = local.selector_labels },
      { for k, v in each.value : k => v if !contains(["name", "externalDNS"], k) },
      try(each.value["type"] == "LoadBalancer", false) ? { "allocateLoadBalancerNodePorts" = false } : {},
    )
  }

  for_each = { for s in var.services : lookup(s, "name", var.name) => s }
}
