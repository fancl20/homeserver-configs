resource "google_storage_bucket" "vault_storage" {
  name = "abaf57ea-fb04-4328-b2d2-1a105ce668cb"
  location = "australia-southeast1"

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}

resource "kubernetes_config_map" "server_config" {
  metadata {
    name      = "vault-helm-chart-value-overrides"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }
  data = {
    "values.yaml" = yamlencode({
      global = {
        enable = false
      }
      server = {
        enabled = true
        extraEnvironmentVars = {
          GOOGLE_APPLICATION_CREDENTIALS = "/etc/secrets/vault-storage/key.json"
        }
        volumeMounts = [{
          name      = "vault-storage"
          mountPath = "/etc/secrets/vault-storage"
          readOnly  = true
        }]
        volumes = [{
          name = "vault-storage"
          secret = {
            secretName = "${kubernetes_secret.vault_storage_key.metadata[0].name}"
          }
        }]
        standalone = {
          enabled = true
          config  = <<-EOT
            ui = true
            listener "tcp" {
              tls_disable = 1
              address = "[::]:8200"
              cluster_address = "[::]:8201"
            }
            storage "gcs" {
              bucket = "${google_storage_bucket.vault_storage.name}"
            }
            seal "gcpckms" {
              project     = "${google_kms_key_ring.vault_unseal.project}"
              region      = "${google_kms_key_ring.vault_unseal.location}"
              key_ring    = "${google_kms_crypto_key.vault_unseal.name}"
              crypto_key  = "${google_kms_crypto_key.vault_unseal.name}"
            }
          EOT
        }
        service = {
          enabled = true
        }
        ingress = {
          enabled = true
          annotations = {
            "nginx.ingress.kubernetes.io/ssl-redirect" = "false"
          }
          hosts = [{
            host = "vault.local.d20.fan"
          }]
          tls = [{
            hosts = ["vault.local.d20.fan"]
          }]
        }
      }
      ui = {
        enabled = true
      }
    })
  }
}
