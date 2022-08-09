resource "kubernetes_config_map" "clash" {
  metadata {
    name = "clash"
  }
  data = {
    "config.yaml" = <<-EOT
    external-controller: 0.0.0.0:9090
    external-ui: clash-dashboard-gh-pages

    interface-name: net1

    ipv6: false

    routing-mark: 1
    tun:
      enable: true
      stack: system

    ebpf:
      redirect-to-tun:
        - net1

    dns:
      enable: true
      listen: 0.0.0.0:53
      enhanced-mode: fake-ip
      fake-ip-range: 198.18.0.0/16
      nameserver:
        - udp://192.168.1.1:53
    
    mode: script
    script:
      code: |
        def main(ctx, metadata):
          ip = metadata["dst_ip"] or ctx.resolve_ip(metadata["host"])
          if ip == "":
            return "DIRECT"

          # Genshin Impact
          if (metadata["network"] == "udp" and
              metadata["dst_port"] in ("22101", "22102") and
              ctx.geoip(ip) == "CN"):
            return "SG1-SG2-CN2"
          if metadata["host"] in (
              "log-upload.mihoyo.com",
              "sdk-static.mihoyo.com",
              "hk4e-sdk.mihoyo.com",
          ):
            return "JP2"

          # Alipay
          if metadata["host"].endswith(".alipay.com"):
            return "JP2"

          # Project Zomboid
          if ip == "43.142.125.244":
            return "SG1-SG2-CN2"

          if ctx.geoip(ip) == "CN":
            return "JP2"

          # Default
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

module "clash_dns" {
  source = "../modules/general-service"
  name   = "clash"
  deployment = {
    containers = [
      {
        name  = "clash"
        image = "ghcr.io/fancl20/clash"
        command = ["/bin/sh", "-e", "-c", <<-EOT
          cat /etc/config/config.yaml /vault/secrets/proxies > /root/.config/clash/config.yaml

          echo -e "nameserver 8.8.8.8\n$(cat /etc/resolv.conf)" > /etc/resolv.conf

          mkdir -p /dev/net
          mknod /dev/net/tun c 10 200
          chmod 600 /dev/net/tun

          ip route add 10.96.0.0/12 via 10.244.0.1 # serviceCIDR
          ip route replace default via 192.168.1.1 dev net1

          exec /opt/bin/clash
          EOT
        ]
        securityContext = {
          capabilities = { add = ["NET_ADMIN", "SYS_MODULE", "SYS_ADMIN"] }
        }
        env = [
          { name = "TZ", value = "Australia/Sydney" },
        ]
        volumeMounts = [
          { name = "config", mountPath = "/etc/config" },
        ]
      },
    ]
    volumes = [
      local.clash_config,
    ]
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
  }
  services = [{
    ports = [
      { name = "webui", protocol = "TCP", port = 80, targetPort = 9090 },
    ]
  }]
  ingress = {
    enabled = true
  }
  vault_injector = {
    role = "proxy"
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
