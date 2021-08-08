# Some of the change require vault restarted to take effect
locals {
  restart_trigger = {
    vault_config_updater_secret = kubernetes_secret.vault_config_updater.metadata[0].resource_version
  }
}

resource "kubernetes_role" "vault_restart" {
  metadata {
    name      = "vault-restart"
    namespace = "vault"
  }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "delete"]
  }
}

resource "kubernetes_service_account" "vault_restart" {
  metadata {
    name      = "vault-restart"
    namespace = "vault"
  }
}

resource "kubernetes_role_binding" "vault_restart" {
  metadata {
    name      = "vault-restart"
    namespace = "vault"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "vault-restart"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_restart.metadata[0].name
    namespace = kubernetes_service_account.vault_restart.metadata[0].namespace
  }
}

resource "kubernetes_job" "vault_restart" {
  metadata {
    name      = "vault-restart"
    namespace = "vault"
  }
  spec {
    template {
      metadata {}
      spec {
        container {
          name  = "vault-restart"
          image = "curlimages/curl"
          command = ["/bin/sh", "-e", "-c", <<-EOT
              set -o pipefail
              # trigger: ${jsonencode(local.restart_trigger)}
              pod_vault() {
                curl -s --fail-with-body -X $1 "https://kubernetes.default.svc/api/v1/namespaces/vault/pods/vault-0" \
                  --header "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
                  --cacert "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt" | tr '\n' ' ' | cut -c 1-1024
              }
              pod_vault DELETE
              while pod_vault GET | grep -q deletionTimestamp; do sleep 1; done
              until curl -s --fail "http://vault.vault:8200/v1/sys/health"; do sleep 1; done
            EOT
          ]
        }
        service_account_name = "vault-restart"
      }
    }
  }
}
