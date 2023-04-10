resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

# TODO: FIXME
# resource "vault_kubernetes_auth_backend_config" "kubernetes" {
#   backend         = vault_auth_backend.kubernetes.path
#   kubernetes_host = "https://kubernetes.default.svc.cluster.local"
# }
