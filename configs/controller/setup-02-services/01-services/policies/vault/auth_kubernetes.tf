resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

resource "vault_policy" "auth_kubernetes_config_writer" {
  name   = "auth_kubernetes_config_writer"
  policy = <<-EOT
    path "auth/${vault_auth_backend.kubernetes.path}/config" {
      capabilities = ["update"]
    }
  EOT
}

resource "vault_token" "config_updater" {
  policies = [
    vault_policy.auth_kubernetes_config_writer.name,
  ]
  renewable = true
  period    = "24h"
  no_parent = true
}

resource "kubernetes_secret" "vault_config_updater" {
  metadata {
    name      = "vault-config-updater"
    namespace = "vault"
  }
  data = {
    "token" = vault_token.config_updater.client_token
  }
}

resource "kubernetes_cron_job" "vault_config_token_renewer" {
  metadata {
    name      = "vault-config-token-renewer"
    namespace = "vault"
  }
  spec {
    concurrency_policy = "Replace"
    schedule           = "0 */12 * * *"
    job_template {
      metadata {}
      spec {
        template {
          metadata {}
          spec {
            container {
              name  = "vault-config-token-renewer"
              image = "curlimages/curl"
              command = ["/bin/sh", "-e", "-c", <<-EOT
                set -o pipefail
                curl -s --fail-with-body \
                  --header "X-Vault-Token: $(cat /etc/secrets/vault-config-updater/token)" \
                  --request POST http://vault.vault:8200/v1/auth/token/renew-self \
                  | sed -E 's/(client_token":")[^"]+/\1/g'
                EOT
              ]
              volume_mount {
                name       = "vault-config-updater"
                mount_path = "/etc/secrets/vault-config-updater"
                read_only  = true
              }
            }
            volume {
              name = "vault-config-updater"
              secret {
                secret_name = kubernetes_secret.vault_config_updater.metadata[0].name
              }
            }
          }
        }
      }
    }
  }
}
