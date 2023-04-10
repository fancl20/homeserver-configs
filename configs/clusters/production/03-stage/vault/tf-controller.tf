# Flux's tf-controller is responsible for vault configuration reconciliation.
# This requires admin role for changing any policy.
resource "vault_policy" "admin" {
  name   = "admin"
  policy = <<-EOT
    # Create and manage ACL policies broadly across Vault
    ## List existing policies
    path "sys/policies/acl" {
      capabilities = ["list"]
    }
    ## Create and manage ACL policies
    path "sys/policies/acl/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }

    # Enable and manage authentication methods broadly across Vault
    ## Manage auth methods broadly across Vault
    path "auth/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
    ## Create, update, and delete auth methods
    path "sys/auth/*" {
      capabilities = ["create", "update", "delete"]
    }
    ## List auth methods
    path "sys/auth" {
      capabilities = ["read"]
    }

    # Enable and manage the key/value secrets engine at `secret/` path
    ## List, create, update, and delete key/value secrets
    path "secret/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
    ## Manage secrets engines
    path "sys/mounts/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
    ## List existing secrets engines.
    path "sys/mounts" {
      capabilities = ["read"]
    }
  EOT
}

# Read secret/gcp/roleset/admin/key
resource "vault_gcp_secret_roleset" "gcp_admin" {
  backend     = vault_gcp_secret_backend.gcp.path
  roleset     = "admin"
  secret_type = "service_account_key"
  project     = google_service_account.vault_gcp.project
  token_scopes = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/ndev.clouddns.readwrite",
  ]

  binding {
    resource = "//cloudresourcemanager.googleapis.com/projects/${google_service_account.vault_gcp.project}"
    roles    = ["roles/owner"]
  }
}

resource "vault_kubernetes_auth_backend_role" "admin" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "admin"
  bound_service_account_names      = ["tf-runner"]
  bound_service_account_namespaces = ["flux-system"]
  token_policies                   = ["default", vault_policy.admin.name]
}
