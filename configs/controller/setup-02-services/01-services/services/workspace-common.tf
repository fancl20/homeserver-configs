resource "kubernetes_config_map" "workspace_common" {
  metadata {
    name = "workspace-common"
  }
  data = {
    sshd_config = <<-EOT
      Port 2222
      PermitRootLogin yes
      ChallengeResponseAuthentication no
      PrintMotd no
      AcceptEnv LANG LC_*
      Subsystem       sftp    /usr/lib/openssh/sftp-server
    EOT
  }
}

locals {
  workspace_common_config = {
    name = "config"
    configMap = {
      name = kubernetes_config_map.workspace_common.metadata[0].name
      items = [
        { key = "sshd_config", path = "sshd_config" },
      ]
    }
  }
}

module "workspace-common" {
  source = "../modules/general-service"
  name   = "workspace-common"
  deployment = {
    image = {
      repository = "ghcr.io/fancl20/coding-workspace"
    }
    args = ["/bin/sh", "-e", "-c", <<-EOT
      cp /vault/secrets/authorized_keys /root/.ssh/
      cp /vault/secrets/id_rsa /root/.ssh/
      chmod 700 /root/.ssh && chmod 600 /root/.ssh/*
      exec /usr/sbin/sshd -D -f /etc/config/sshd_config
      EOT
    ]
    env = [
      { name = "TZ", value = "Australia/Sydney" },
    ]
    volumeMounts = [
      { name = "config", mountPath = "/etc/config" },
      { name = "data", mountPath = "/root", subPath = "workspaces/common" },
      { name = "ssh", mountPath = "/root/.ssh" },
    ]
    volumes = [
      local.workspace_common_config,
      local.mass_storage_volume,
      { name = "ssh", emptyDir = {} },
    ]
  }
  services = {
    workspace-common = {
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
      authorized_keys = {
        path     = "homeserver/data/ssh"
        template = <<-EOT
          {{ with secret "homeserver/data/ssh" -}}
          {{ .Data.data.public_key }}
          {{- end }}
        EOT
      }
      id_rsa = {
        path     = "homeserver/data/ssh"
        template = <<-EOT
          {{ with secret "homeserver/data/ssh" -}}
          {{ .Data.data.private_key }}
          {{- end }}
        EOT
      }
    }
  }
  domain_suffix = var.domain_suffix
}
