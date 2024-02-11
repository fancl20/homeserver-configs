# Certbot requires gcp acount for DNS-01 challenge.
resource "vault_policy" "certbot" {
  name   = "kubernetes_certbot"
  policy = <<-EOT
    path "gcp/roleset/certbot/key" {
      capabilities = ["create", "read", "update"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "certbot" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "certbot"
  bound_service_account_names      = ["certbot", "cert-manager"]
  bound_service_account_namespaces = ["default", "cert-manager"]
  token_policies                   = ["default", vault_policy.certbot.name]
}

resource "vault_gcp_secret_roleset" "certbot" {
  backend     = vault_gcp_secret_backend.gcp.path
  roleset     = "certbot"
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

# ExternalDNS and Bind9 share the secret key for BIND.
resource "vault_policy" "external_dns" {
  name   = "kubernetes_external_dns"
  policy = <<-EOT
    path "homeserver/data/bind9" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "external_dns" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "external_dns"
  bound_service_account_names      = ["bind9", "external-dns"]
  bound_service_account_namespaces = ["default"]
  token_policies                   = ["default", vault_policy.external_dns.name]
}

# Rclone requires uploading to backblaze storage.
resource "vault_policy" "data_backup" {
  name   = "kubernetes_data_backup"
  policy = <<-EOT
    path "homeserver/data/backblaze" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "data_backup" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "data_backup"
  bound_service_account_names      = ["rclone"]
  bound_service_account_namespaces = ["default"]
  token_policies                   = ["default", vault_policy.data_backup.name]
}

# SFTP requires sharing password with some clients (infuse).
resource "vault_policy" "data_ssh" {
  name   = "kubernetes_data_ssh"
  policy = <<-EOT
    path "homeserver/data/sftp" {
      capabilities = ["read"]
    }
  EOT
}
resource "vault_kubernetes_auth_backend_role" "data_ssh" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "data_ssh"
  bound_service_account_names      = ["sftp"]
  bound_service_account_namespaces = ["default"]
  token_policies                   = ["default", vault_policy.data_ssh.name]
}

# dae requires proxy information.
resource "vault_policy" "proxy" {
  name   = "kubernetes_proxy"
  policy = <<-EOT
    path "homeserver/data/dae" {
      capabilities = ["read"]
    }
  EOT
}
resource "vault_kubernetes_auth_backend_role" "proxy" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "proxy"
  bound_service_account_names      = ["dae"]
  bound_service_account_namespaces = ["default"]
  token_policies                   = ["default", vault_policy.proxy.name]
}

# Workspace requires private key for using Git inside.
resource "vault_policy" "workspace_ssh" {
  name   = "kubernetes_workspace_ssh"
  policy = <<-EOT
    path "homeserver/data/ssh" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "workspace_ssh" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "workspace_ssh"
  bound_service_account_names      = ["workspace-common"]
  bound_service_account_namespaces = ["default"]
  token_policies                   = ["default", vault_policy.workspace_ssh.name]
}
