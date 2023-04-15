resource "vault_kubernetes_auth_backend_role" "notifier" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "notifier"
  bound_service_account_names      = ["notification-controller"]
  bound_service_account_namespaces = ["flux-system"]
  token_policies                   = ["default"]
}
