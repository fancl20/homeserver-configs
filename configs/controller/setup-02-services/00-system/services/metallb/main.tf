resource "kubernetes_namespace" "metallb" {
  metadata {
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit" = "privileged"
      "pod-security.kubernetes.io/warn" = "privileged"
    }
    name = "metallb-system"
  }
}

resource "helm_release" "metallb" {
  name             = "metallb"
  namespace        = "metallb-system"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  version          = "0.13.4"

  depends_on = [kubernetes_namespace.metallb]
}

