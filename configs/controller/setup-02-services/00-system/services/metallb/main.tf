resource "helm_release" "metallb" {
  name       = "metallb"
  namespace  = "metallb-system"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  values = [
    "${file("${path.module}/values.yaml")}"
  ]
  create_namespace = true
}
