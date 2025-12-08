resource "google_storage_bucket" "vault_storage" {
  name     = "abaf57ea-fb04-4328-b2d2-1a105ce668cb"
  location = "australia-southeast1"

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}

resource "kubernetes_config_map" "server_config" {
  metadata {
    name      = "vault-helm-chart-value-overrides"
    namespace = "vault"
  }
  data = {
    "values.yaml" = yamlencode({
      server = {
        enabled = true
        extraEnvironmentVars = {
          GOOGLE_APPLICATION_CREDENTIALS = "/etc/secrets/vault-storage/key.json"
        }
        volumes = [{
          name = "vault-storage"
          secret = {
            secretName = "${kubernetes_secret_v1.vault_storage_key.metadata[0].name}"
          }
        }]
        volumeMounts = [{
          name      = "vault-storage"
          mountPath = "/etc/secrets/vault-storage"
          readOnly  = true
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
        dataStorage = {
          enabled = false
        }
      }
      injector = {
        enabled = false
      }
    })
  }
}
