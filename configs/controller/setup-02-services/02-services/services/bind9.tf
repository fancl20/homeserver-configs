resource "kubernetes_config_map" "bind9" {
  metadata {
    name = "bind9"
  }
  data = {
    "named.conf" = <<-EOT
      options {
        directory "/var/cache/bind";
        query-source address * port *; # Exchange port between DNS servers
        forward only;
        forwarders { 8.8.8.8; 8.8.4.4; };
        auth-nxdomain no; # conform to RFC1035
        interface-interval 0; # From 9.9.5 ARM, disables interfaces scanning to prevent unwanted stop listening
        listen-on-v6 { none; }; # Listen on local interfaces only(IPV4)
        listen-on port 5353 { 0.0.0.0/0; };
        allow-transfer { none; }; # Do not transfer the zone information to the secondary DNS
        allow-query { any; };
        allow-recursion { any; };
        max-cache-size 64m;
        max-cache-ttl 60;
        max-ncache-ttl 60;
        version none; # Do not make public version of BIND
      };
      controls { };

      include "/vault/secrets/bind9_externaldns_key";
      zone "local.d20.fan" {
        type master;
        file "/etc/bind/pri/local.d20.fan.zone";
        allow-transfer { key "externaldns-key"; };
        update-policy { grant externaldns-key zonesub ANY; };
      };
    EOT
    "local.d20.fan.zone" = <<-EOT
      $TTL 60 ; 1 minute
      @                               IN SOA  local.d20.fan. root.local.d20.fan. (
                                      16         ; serial
                                      60         ; refresh (1 minute)
                                      60         ; retry (1 minute)
                                      60         ; expire (1 minute)
                                      60         ; minimum (1 minute)
                                      )
                              NS      ns.local.d20.fan.
      ns                      A       192.168.1.3
    EOT
  }
}

locals {
  bind9_config = {
    name = "config"
    configMap = {
      name = kubernetes_config_map.bind9.metadata[0].name
      items = [
        { key = "named.conf", path = "named.conf" },
        { key = "local.d20.fan.zone", path = "local.d20.fan.zone" },
      ]
    }
  }
}

module "bind9" {
  source = "../modules/general-service"
  name = "bind9"
  deployment = {
    image = {
      repository = "internetsystemsconsortium/bind9"
      tag = "9.16"
    }
    command = [ "/bin/sh" ]
    args = [ "-e", "-c", <<-EOT
        mkdir -p /etc/bind/pri
        cp /etc/config/named.conf /etc/bind/
        cp /etc/config/local.d20.fan.zone /etc/bind/pri/
        chown -R bind:bind /etc/bind/ && chmod -R 755 /etc/bind
        chown -R bind:bind /var/cache/bind && chmod -R 755 /var/cache/bind
        chown -R bind:bind /var/lib/bind && chmod -R 755 /var/lib/bind
        chown -R bind:bind /run/named && chmod -R 755 /run/named
        /usr/sbin/named -g -c /etc/bind/named.conf -u bind
      EOT
    ]
    resources = {
      requests = { memory = "128Mi", cpu = "100m" }
      limits = { memory = "128Mi", cpu = "200m" }
    }
    volumeMounts = [
      { name = "config", mountPath = "/etc/config" },
      { name = "data", mountPath = "/etc/bind", subPath = "bind9/etc/bind" },
      { name = "data", mountPath = "/var/cache/bind", subPath = "bind9/var/cache/bind" },
      { name = "data", mountPath = "/var/lib/bind", subPath = "bind9/var/lib/bind" },
    ]
    volumes = [
      local.bind9_config,
      local.mass_storage_volume,
    ]
  }
  services = {
    bind9 = {
      ports = [
        { name = "dns-udp", protocol = "UDP", port = 53, targetPort = 5353 },
        { name = "dns-tcp", protocol = "TCP", port = 53, targetPort = 5353 },
      ]
      type = "LoadBalancer"
      loadBalancerIP = var.dns_static_ip
    }
  }
  vault_injector = {
    role = "homeserver"
    secrets = {
      bind9_externaldns_key = {
        path = "homeserver/data/bind9"
        template = <<-EOT
          {{ with secret "homeserver/data/bind9" -}}
          key externaldns-key {
            algorithm {{ .Data.data.externaldns_key_algorithm }};
            secret "{{ .Data.data.externaldns_key_secret }}";
          };
          {{- end }}
        EOT
      }
    }
  }
}