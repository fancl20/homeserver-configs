resource "helm_release" "metallb" {
  name       = "metallb"
  namespace  = "metallb-system"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  values = [
    yamlencode({
      configInline = {
        address-pools = [
          {
            name      = "default"
            protocol  = "layer2"
            addresses = ["192.168.1.5-192.168.1.37"]
          },
          {
            name        = "reserved"
            protocol    = "layer2"
            addresses   = ["192.168.1.1-192.168.1.4"]
            auto-assign = false
          },
        ]
      }
    })
  ]
  create_namespace = true
}
