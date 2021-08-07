module "rclone_vault_injector" {
  source = "../modules/vault-injector"
  role   = "homeserver"
  secrets = {
    config = {
      path     = "homeserver/data/backblaze"
      template = <<-EOT
        {{ with secret "homeserver/data/backblaze" -}}
        [remote]
        type = b2
        account = {{ .Data.data.account }}
        key = {{ .Data.data.key }}
        {{- end }}
      EOT
    }
  }
}

resource "kubernetes_cron_job" "rclone" {
  metadata {
    name = "rclone"
  }
  spec {
    concurrency_policy = "Forbid"
    schedule           = "0 04 * * *"
    job_template {
      metadata {}
      spec {
        template {
          metadata {
            annotations = module.rclone_vault_injector.annotations
          }
          spec {
            container {
              name  = "rclone-shared"
              image = "rclone/rclone"
              args  = ["sync", "--config=/vault/secrets/config", "/backup", "remote:homeserver", "--fast-list", "--exclude", "/downloads/"]
              volume_mount {
                name       = "data"
                mount_path = "/backup"
                sub_path   = "shared"
              }
            }
            container {
              name  = "rclone-vault"
              image = "rclone/rclone"
              args  = ["sync", "--config=/vault/secrets/config", "/backup", "remote:homeserver-vault", "--fast-list"]
              volume_mount {
                name       = "vault"
                mount_path = "/backup"
              }
            }
            volume {
              name = "data"
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim.mass_storage.metadata[0].name
              }
            }
            volume {
              name = "vault"
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim.vault_storage_backup.metadata[0].name
              }
            }
            restart_policy = "OnFailure"
          }
        }
      }
    }
  }
}