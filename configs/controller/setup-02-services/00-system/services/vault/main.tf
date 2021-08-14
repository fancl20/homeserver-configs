variable "domain_suffix" {
  type = string
}

resource "helm_release" "vault" {
  name       = "vault"
  namespace  = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "v0.14.0"
  values = [
    yamlencode({
      server = {
        enabled = true
        postStart = ["/bin/sh", "-e", "-c", <<-EOT
          # Exit normally if token not exist - as it probablly means we haven't
          # finished the initilization.
          if [ ! -f "/etc/secrets/vault-config-updater/token" ]; then exit 0; fi
          until vault status &> /dev/null; do sleep 1; done

          /bin/vault login token=@/etc/secrets/vault-config-updater/token
          /bin/vault write auth/kubernetes/config \
            issuer="https://kubernetes.default.svc" \
            token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token \
            kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
            kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          EOT
        ]
        volumeMounts = [{
          name      = "vault-kms"
          mountPath = "/etc/secrets/vault-kms"
          readOnly  = true
          }, {
          name      = "vault-config-updater"
          mountPath = "/etc/secrets/vault-config-updater"
          readOnly  = true
        }]
        volumes = [{
          name = "vault-kms"
          secret = {
            secretName = "${kubernetes_secret.vault_kms_key.metadata[0].name}"
          }
          }, {
          name = "vault-config-updater"
          secret = {
            secretName = "vault-config-updater"
            optional   = true
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
            host = "vault.${var.domain_suffix}"
          }]
          tls = [{
            hosts = [
              "vault.${var.domain_suffix}"
            ]
          }]
        }
        dataStorage = {
          enabled      = true
          size         = "${kubernetes_persistent_volume.vault_storage.spec[0].capacity.storage}"
          storageClass = "${kubernetes_persistent_volume.vault_storage.spec[0].storage_class_name}"
          accessMode   = "ReadWriteOnce"
        }
      }
      injector = {
        enabled = true
      }
      ui = {
        enabled = true
      }
      csi = {
        enabled = false
      }
    })
  ]
  create_namespace = true
  recreate_pods    = true
}
