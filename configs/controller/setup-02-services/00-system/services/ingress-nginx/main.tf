variable "domain_tls_ref" {
  type = string
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  namespace  = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.0.3"
  values = [
    yamlencode({
      controller = {
        extraArgs = {
          default-ssl-certificate = "default/${var.domain_tls_ref}"
        }
        config = {
          enable-real-ip = "true"
        }
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
        }
        watchIngressWithoutClass = "true"
      }
    })
  ]
  create_namespace = true
}
