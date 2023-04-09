resource "kubernetes_config_map" "server_config" {
  metadata {
    name      = "vault-helm-chart-value-overrides"
    namespace = "vault"
  }
  data = {
    "values.yaml" = yamlencode({
      server = {
        enabled = true
        volumeMounts = [{
          name      = "vault-kms"
          mountPath = "/etc/secrets/vault-kms"
          readOnly  = true
        }]
        volumes = [{
          name = "vault-kms"
          secret = {
            secretName = "${kubernetes_secret.vault_kms_key.metadata[0].name}"
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
            storage "file" {
              path = "/vault/data"
            }
            seal "gcpckms" {
              credentials = "/etc/secrets/vault-kms/key.json"
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
        dataStorage = {
          enabled      = true
          size         = "10Gi"
          storageClass = "vault-storage"
          accessMode   = "ReadWriteOnce"
        }
      }
      injector = {
        enabled = true
      }
      ui = {
        enabled = true
      }
    })
  }
}
