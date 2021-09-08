resource "kubernetes_config_map" "clash" {
  metadata {
    name = "clash"
  }
  data = {
    "config.yaml" = <<-EOT
    external-controller: 0.0.0.0:9090
    external-ui: clash-dashboard-gh-pages
    
    interface-name: net1
    
    tun:
      enable: true
      stack: gvisor
    
    dns:
      enable: true
      listen: 0.0.0.0:53
      enhanced-mode: fake-ip 
      fake-ip-range: 198.18.0.1/16
      nameserver:
        - udp://192.168.1.1:53
    
    mode: script
    script:
      code: |
        def main(ctx, metadata):
          ip = metadata["dst_ip"] or ctx.resolve_ip(metadata["host"])
          if ip == "":
            return "DIRECT"
          if metadata["network"] == "udp" and ctx.geoip(ip) == "CN":
            return "JP1-JP2"
          return "DIRECT"
    EOT
  }
}

locals {
  clash_config = {
    name = "config"
    configMap = {
      name = kubernetes_config_map.clash.metadata[0].name
      items = [
        { key = "config.yaml", path = "config.yaml" },
      ]
    }
  }
}

module "clash" {
  source = "../modules/general-service"
  name   = "clash"
  deployment = {
    image = {
      repository = "ghcr.io/fancl20/clash"
      pullPolicy = "Always"
    }
    podAnnotations = {
      "k8s.v1.cni.cncf.io/networks" = jsonencode([
        {
          name    = "macvlan"
          ips     = ["192.168.1.245/24"]
          mac     = "26:1e:94:c2:23:40"
          gateway = ["192.168.1.1"]
        }
      ])
    }
    securityContext = {
      capabilities = { add = ["NET_ADMIN"] }
    }
    env = [
      { name = "TZ", value = "Australia/Sydney" },
    ]
    volumeMounts = [
      { name = "config", mountPath = "/etc/config" },
    ]
    volumes = [
      local.clash_config,
    ]
  }
  services = {
    clash = {
      ports = [
        { name = "webui", protocol = "TCP", port = 80, targetPort = 9090 },
      ]
    }
  }
  ingress = {
    enabled = true
  }
  vault_injector = {
    role = "homeserver"
    secrets = {
      proxies = {
        path     = "homeserver/data/clash"
        template = <<-EOT
          {{ with secret "homeserver/data/clash" -}}
          {{ .Data.data.proxies }}
          {{- end }}
        EOT
      }
    }
  }
  domain_suffix = var.domain_suffix
}
