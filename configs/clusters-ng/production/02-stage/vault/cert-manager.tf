# Certbot requires gcp acount for DNS-01 challenge.
resource "vault_policy" "cert_manager" {
  name   = "kubernetes_cert_manager"
  policy = <<-EOT
    path "gcp/roleset/cert_manager/key" {
      capabilities = ["create", "read", "update"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "cert_manager" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "cert_manager"
  bound_service_account_names      = ["cert-manager"]
  bound_service_account_namespaces = ["cert-manager"]
  token_policies                   = ["default", vault_policy.cert_manager.name]
}

resource "vault_gcp_secret_roleset" "cert_manager" {
  backend     = vault_gcp_secret_backend.gcp.path
  roleset     = "cert-manager"
  secret_type = "service_account_key"
  project     = google_service_account.vault_gcp.project
  token_scopes = [
    "https://www.googleapis.com/auth/ndev.clouddns.readwrite",
    "https://www.googleapis.com/auth/cloud-platform.read-only",
  ]

  binding {
    resource = "//cloudresourcemanager.googleapis.com/projects/${google_service_account.vault_gcp.project}"
    roles = [
      "roles/dns.admin",
    ]
  }
}
