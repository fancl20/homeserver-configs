local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('dae')
.PodContainers([{
  image: images.dae,
  command: ['/bin/bash', '-ex', '-c', |||
    mkdir -p /etc/dae
    cat /config/config.dae <(echo) /vault/secrets/node.dae > /etc/dae/config.dae
    chmod 0600 /etc/dae/config.dae

    mount bpffs /sys/fs/bpf/ -t bpf

    ip route replace 10.96.0.0/12 via 10.244.0.1 # serviceCIDR
    ip route replace default via 192.168.1.1 dev net1

    exec /opt/dae/dae-linux-x86_64 run --disable-timestamp -c /etc/dae/config.dae
  |||],
  securityContext: {
    capabilities: { add: ['NET_ADMIN', 'SYS_MODULE', 'SYS_ADMIN'] },
  },
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
  ],
  volumeMounts: [
    { name: 'config', mountPath: '/config' },
  ],
}])
.PodAnnotations({
  'k8s.v1.cni.cncf.io/networks': std.manifestJson([
    {
      name: 'macvlan',
      ips: ['192.168.1.245/24'],
      mac: '26:1e:94:c2:23:40',
      gateway: ['192.168.1.1'],
    },
  ]),
})
.PodVolumes([
  { name: 'config', configMap: { name: 'dae' } },
])
.PodSecurityContext({
  sysctls: [
    { name: 'net.ipv4.conf.net1.forwarding', value: '1' },
    { name: 'net.ipv6.conf.net1.forwarding', value: '1' },
    { name: 'net.ipv4.conf.net1.send_redirects', value: '0' },
    { name: 'net.ipv4.ip_forward', value: '1' },
  ],
})
.VaultInjector('proxy', {
  'node.dae': {
    path: 'homeserver/data/dae',
    template: |||
      {{ with secret "homeserver/data/dae" -}}
      {{ index .Data.data.config }}
      {{- end }}
    |||,
  },
})
.Ingress()
.Kustomize()
.Config('config.dae', |||
  global {
    lan_interface: net1

    log_level: info
    allow_insecure: false

    auto_config_kernel_parameter: false
    auto_config_firewall_rule: true
  }
  dns {
    upstream {
      googledns: 'udp+tcp://dns.google.com:53'
    }
    routing {
      request {
        fallback: googledns
      }
      response {
        upstream(googledns) -> accept
        fallback: accept
      }
    }
  }
  routing{
    dip(geoip:private) -> direct

    dip(geoip:cn) && l4proto(udp) && dport(22101, 22102) -> game
    domain(suffix: mihoyo.com, suffix: yuanshen.com) -> general

    fallback: direct
  }
  group {
    general {
      filter: name(JP2)
      policy: min_moving_avg
    }
    game {
      filter: name(SG1-SG2-CN2)
      policy: min_moving_avg
    }
  }
|||)
