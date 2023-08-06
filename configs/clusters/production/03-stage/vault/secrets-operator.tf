# Notifier require slack token to send notification.
resource "vault_policy" "notifier" {
  name   = "notifier"
  policy = <<-EOT
    path "homeserver/data/slack" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "notifier" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "notifier"
  bound_service_account_names      = ["notification-controller"]
  bound_service_account_namespaces = ["flux-system"]
  token_policies                   = ["default", vault_policy.notifier.name]
}

# Source controller require github personal access token for updating source.
resource "vault_policy" "source_controller" {
  name   = "source-controller"
  policy = <<-EOT
    path "homeserver/data/github_pat" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "source_controller" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "source-controller"
  bound_service_account_names      = ["source-controller"]
  bound_service_account_namespaces = ["flux-system"]
  token_policies                   = ["default", vault_policy.source_controller.name]
}
