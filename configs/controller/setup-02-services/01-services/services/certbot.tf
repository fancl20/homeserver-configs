resource "kubernetes_role" "default_secret_writer" {
  metadata {
    name = "secret-writer"
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "create", "update", "patch"]
  }
}

resource "kubernetes_service_account" "certbot" {
  metadata {
    name = "certbot"
  }
}

resource "kubernetes_role_binding" "certbot" {
  metadata {
    name = "certbot"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.default_secret_writer.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.certbot.metadata[0].name
    namespace = kubernetes_service_account.certbot.metadata[0].namespace
  }
}

module "certbot_vault_injector" {
  source = "../modules/vault-injector"
  role   = "certbot"
  secrets = {
    gcp = {
      path     = "gcp/roleset/certbot/key"
      template = <<-EOT
        {{ with secret "gcp/roleset/certbot/key" -}}
        {{ .Data.private_key_data }}
        {{- end }}
      EOT
    }
  }
}

resource "kubernetes_cron_job" "certbot" {
  metadata {
    name = "certbot"
  }
  spec {
    concurrency_policy = "Forbid"
    schedule           = "0 0 1 * *"
    job_template {
      metadata {}
      spec {
        template {
          metadata {
            annotations = module.certbot_vault_injector.annotations
          }
          spec {
            security_context {
              run_as_user = 0
            }
            init_container {
              name  = "certbot"
              image = "certbot/dns-google"
              command = ["/bin/sh", "-e", "-c", <<-EOT
                base64 -d /vault/secrets/gcp > /tmp/key.json
                chmod 600 /tmp/key.json
                certbot certonly \
                  --agree-tos \
                  --no-eff-email \
                  --preferred-chain "ISRG Root X1" \
                  -m fancl20@gmail.com \
                  --cert-name local \
                  --dns-google \
                  --dns-google-credentials /tmp/key.json \
                  -d '*.local.d20.fan'
                EOT
              ]
              volume_mount {
                name       = "certs"
                mount_path = "/etc/letsencrypt/"
              }
            }
            container {
              name  = "update-secret"
              image = "bitnami/kubectl"
              command = ["/bin/sh", "-e", "-c", <<-EOT
                kubectl create secret tls "${var.domain_tls_ref}" \
                  --dry-run=client \
                  --key=/etc/letsencrypt/live/local/privkey.pem \
                  --cert=/etc/letsencrypt/live/local/cert.pem \
                  -o yaml | kubectl apply -f -
                EOT
              ]
              volume_mount {
                name       = "certs"
                mount_path = "/etc/letsencrypt/"
              }
            }
            volume {
              name = "certs"
              empty_dir {}
            }
            restart_policy       = "OnFailure"
            service_account_name = kubernetes_service_account.certbot.metadata[0].name
          }
        }
      }
    }
  }
}
