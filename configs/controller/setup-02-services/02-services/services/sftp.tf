module "sftp" {
  source = "../modules/general-service"
  name   = "sftp"
  deployment = {
    image = {
      repository = "ghcr.io/linuxserver/openssh-server"
    }
    env = [
      { name = "TZ", value = "Australia/Sydney" },
      { name = "PUID", value = "0" },
      { name = "GUID", value = "0" },
      { name = "PUBLIC_KEY_FILE", value = "/vault/secrets/sftp_public_key" },
      { name = "PASSWORD_ACCESS", value = "true" },
      { name = "USER_PASSWORD_FILE", value = "/vault/secrets/sftp_user_password" },
      { name = "USER_NAME", value = "fancl20" },
    ]
    volumeMounts = [
      { name = "data", mountPath = "/shared", subPath = "shared" },
    ]
    volumes = [
      local.mass_storage_volume,
    ]
  }
  services = {
    sftp = {
      ports = [
        { name = "ssh", protocol = "TCP", port = 22, targetPort = 2222 },
      ]
      type        = "LoadBalancer"
      externalDNS = true
    }
  }
  vault_injector = {
    role = "homeserver"
    secrets = {
      sftp_public_key = {
        path     = "homeserver/data/sftp"
        template = <<-EOT
          {{ with secret "homeserver/data/sftp" -}}
          {{ .Data.data.public_key }}
          {{- end }}
        EOT
      }
      sftp_user_password = {
        path     = "homeserver/data/sftp"
        template = <<-EOT
          {{ with secret "homeserver/data/sftp" -}}
          {{ .Data.data.user_password }}
          {{- end }}}
        EOT
      }
    }
  }
  domain_suffix = var.domain_suffix
}