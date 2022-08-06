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
      listen: 127.0.0.1:1153
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

    "Corefile" = <<-EOT
    . {
      forward . 192.168.1.1
      log
      errors
    }
    #mihoyo.com {
    #  forward . 127.0.0.1:1153
    #  log
    #  errors
    #}
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
        { key = "Corefile", path = "Corefile" },
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
        name    = "clash-dns"
        image   = "coredns/coredns"
        command = ["/coredns", "-conf", "/config/Corefile"]
        env = [
          { name = "TZ", value = "Australia/Sydney" },
        ]
        volumeMounts = [
          { name = "config", mountPath = "/config" },
        ]
      },
      {
        name  = "clash"
        image = "ghcr.io/fancl20/clash"
        command = ["/bin/sh", "-e", "-c", <<-EOT
          cat /etc/config/config.yaml /vault/secrets/proxies > /root/.config/clash/config.yaml

          NETFILTER_MARK=1
          IPROUTE2_TABLE_ID=100

          ip route add 10.96.0.0/12 via 10.244.0.1 # serviceCIDR
          ip route replace default via 192.168.1.1 dev net1
          ip route replace local default dev lo table "$IPROUTE2_TABLE_ID"
          ip rule add fwmark "$NETFILTER_MARK" lookup "$IPROUTE2_TABLE_ID"

          nft -f - << EOF
          table clash
          flush table clash
          table clash {
            chain input {
              type filter hook prerouting priority mangle; policy accept;
              ip protocol != { tcp, udp } accept
              ip daddr { 127.0.0.0/8, 224.0.0.0/4, 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 169.254.0.0/16, 240.0.0.0/4 } accept

              ip daddr { 192.18.0.0/16, 203.107.0.0/16, 101.226.0.0/16 } goto proxy
              ip daddr { 43.142.125.244 } goto proxy # Project Zomboid
              udp dport { 22101, 22102 } goto proxy
            }
            chain proxy {
              ip protocol tcp mark set $NETFILTER_MARK tproxy to 127.0.0.1:7893
              ip protocol udp mark set $NETFILTER_MARK tproxy to 127.0.0.1:7893
            }
          }
          EOF

          exec /opt/bin/clash
          EOT
        ]
        securityContext = {
          capabilities = { add = ["NET_ADMIN"] }
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
