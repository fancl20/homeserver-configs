resource "vault_kubernetes_auth_backend_role" "certbot" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "certbot"
  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = ["*"]
  token_policies                   = ["default", "certbot"]
}

resource "vault_policy" "certbot" {
  name = "certbot"

  policy = <<-EOT
    path "gcp/roleset/certbot/key" {
      capabilities = ["read"]
    }
  EOT
}
