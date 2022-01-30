resource "kubernetes_config_map" "clash" {
  metadata {
    name = "clash"
  }
  data = {
    "config.yaml" = <<-EOT
    tproxy-port: 7893

    external-controller: 0.0.0.0:9090
    external-ui: clash-dashboard-gh-pages

    interface-name: net1

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

          # Genshin Impact
          if (metadata["network"] == "udp" and
              metadata["dst_port"] in ("22101", "22102") and
              ctx.geoip(ip) == "CN"):
            return "JP1-JP2"
          if metadata["host"] in (
              "log-upload.mihoyo.com",
              "sdk-static.mihoyo.com",
              "hk4e-sdk.mihoyo.com",
          ):
            return "JP1-JP2"

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

module "clash" {
  source = "../modules/general-service"
  name   = "clash"
  deployment = {
    image = {
      repository = "ghcr.io/fancl20/clash"
    }
    command = ["/bin/sh", "-e", "-c", <<-EOT
      cat /etc/config/config.yaml /vault/secrets/proxies > /root/.config/clash/config.yaml

      NETFILTER_MARK=1
      IPROUTE2_TABLE_ID=100

      ip route replace local default dev lo table "$IPROUTE2_TABLE_ID"
      ip rule add fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID"

      nft -f - << EOF
      define LOCAL_SUBNET = { 127.0.0.0/8, 224.0.0.0/4, 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 169.254.0.0/16, 240.0.0.0/4 }
      table clash
      flush table clash
      table clash {
          chain local {
              type filter hook prerouting priority 0;
              ip protocol != { tcp, udp } accept
              ip daddr \$LOCAL_SUBNET accept

              ip protocol tcp mark set $NETFILTER_MARK tproxy to 127.0.0.1:7893
              ip protocol udp mark set $NETFILTER_MARK tproxy to 127.0.0.1:7893
          }
      }
      EOF

      exec /opt/bin/clash
      EOT
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
