resource "kubernetes_manifest" "advertisement" {
  manifest = {
    "apiVersion" = "metallb.io/v1beta1"
    "kind"       = "L2Advertisement"
    "metadata" = {
      "name"      = "default"
      "namespace" = "metallb-system"
    }
  }
}

resource "kubernetes_manifest" "address_pool_default" {
  manifest = {
    "apiVersion" = "metallb.io/v1beta1"
    "kind"       = "IPAddressPool"
    "metadata" = {
      "name"      = "default"
      "namespace" = "metallb-system"
    }
    "spec" = {
      "addresses" = ["192.168.1.5-192.168.1.37"]
    }
  }
}

resource "kubernetes_manifest" "address_pool_reserved" {
  manifest = {
    "apiVersion" = "metallb.io/v1beta1"
    "kind"       = "IPAddressPool"
    "metadata" = {
      "name"      = "reserved"
      "namespace" = "metallb-system"
    }
    "spec" = {
      "addresses"  = ["192.168.1.1-192.168.1.4"]
      "autoAssign" = false
    }
  }
}
