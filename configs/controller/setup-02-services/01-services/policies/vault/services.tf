resource "vault_kubernetes_auth_backend_role" "certbot" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "certbot"
  bound_service_account_names      = ["certbot"]
  bound_service_account_namespaces = ["default"]
  token_policies                   = ["default", vault_policy.certbot.name]
}

resource "vault_policy" "certbot" {
  name   = "kubernetes_certbot"
  policy = <<-EOT
    path "gcp/roleset/certbot/key" {
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

resource "vault_policy" "external_dns" {
  name   = "kubernetes_external_dns"
  policy = <<-EOT
    path "homeserver/data/bind9" {
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

resource "vault_policy" "data_backup" {
  name   = "kubernetes_data_backup"
  policy = <<-EOT
    path "homeserver/data/backblaze" {
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

resource "vault_policy" "data_ssh" {
  name   = "kubernetes_data_ssh"
  policy = <<-EOT
    path "homeserver/data/sftp" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "proxy" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "proxy"
  bound_service_account_names      = ["clash"]
  bound_service_account_namespaces = ["default"]
  token_policies                   = ["default", vault_policy.proxy.name]
}

resource "vault_policy" "proxy" {
  name   = "kubernetes_proxy"
  policy = <<-EOT
    path "homeserver/data/clash" {
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

resource "vault_policy" "workspace_ssh" {
  name   = "kubernetes_workspace_ssh"
  policy = <<-EOT
    path "homeserver/data/ssh" {
      capabilities = ["read"]
    }
  EOT
}
