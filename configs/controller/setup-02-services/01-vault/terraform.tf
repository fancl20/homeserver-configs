resource "kubernetes_service_account" "terraform" {
  metadata {
    name = "terraform"
  }
}

resource "kubernetes_cluster_role_binding" "terraform" {
  metadata {
    name = "terraform"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.terraform.metadata[0].name
    namespace = kubernetes_service_account.terraform.metadata[0].namespace
  }
}

resource "vault_policy" "vault_sys_admin" {
  name   = "vault_sys_admin"
  policy = <<-EOT
    path "sys/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
  EOT
}

resource "vault_policy" "vault_auth_admin" {
  name   = "vault_auth_admin"
  policy = <<-EOT
    path "auth/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "terraform" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "terraform"
  bound_service_account_names      = [kubernetes_service_account.terraform.metadata[0].name]
  bound_service_account_namespaces = [kubernetes_service_account.terraform.metadata[0].namespace]
  token_ttl                        = 1200
  token_policies = [
    "default",
    vault_policy.vault_sys_admin.name,
    vault_policy.vault_auth_admin.name,
  ]
}