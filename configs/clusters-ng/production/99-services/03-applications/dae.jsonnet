local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('dae')
.PodContainers([{
  image: images.dae,
  command: ['/bin/bash', '-ex', '-c', |||
    mount bpffs /sys/fs/bpf/ -t bpf

    sysctl -w net.ipv4.conf.net1.forwarding=1
    sysctl -w net.ipv6.conf.net1.forwarding=1
    sysctl -w net.ipv4.conf.net1.send_redirects=0

    ip route replace 10.96.0.0/12 via 10.244.0.1 dev eth0 onlink # serviceCIDR
    ip route replace default via 192.168.1.1 dev net1

    exec /opt/dae/dae-linux-x86_64_v3_avx2 run --disable-timestamp -c /etc/dae/config.dae
  |||],
  securityContext: {
    privileged: true,
    capabilities: { add: ['NET_ADMIN', 'BPF', 'SYS_ADMIN'] },
  },
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
  ],
  volumeMounts: [
    { name: 'config', mountPath: '/etc/dae' },
  ],
}])
.PodAnnotations({
  'k8s.v1.cni.cncf.io/networks': std.manifestJson([
    {
      name: 'macvlan-static',
      ips: ['192.168.1.247/24'],
    },
  ]),
})
.PodVolumes([{
  name: 'config',
  projected: {
    defaultMode: std.parseOctal('0600'),
    sources: [
      { configMap: { name: 'dae' } },
      { secret: { name: 'dae' } },
    ],
  },
}])
.OnePassword(spec={
  dataFrom: [{
    extract: { key: 'Dae Configs', property: 'node.dae' },
  }],
})
.Ingress()
.Kustomize()
.Config('config.dae', |||
  global {
    lan_interface: net1

    log_level: info
    allow_insecure: false

    tcp_check_url: 'https://dns.alidns.com/'
    udp_check_dns: 'dns.alidns.com:53'

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

    domain(full: autopatchcn.yuanshen.com) -> general-sg
    dip(geoip:cn) && l4proto(udp) && dport(22101, 22102) -> game
    domain(suffix: mihoyo.com, suffix: yuanshen.com) -> general-cn

    fallback: direct
  }
  group {
    general-sg {
      filter: name(SG1)
      policy: min_moving_avg
    }
    general-cn {
      filter: name(SG1-SG2-CN2)
      policy: min_moving_avg
    }
    game {
      filter: name(SG1-SG2-CN2-CN3)
      policy: min_moving_avg
    }
  }
  include {
    node.dae
  }
|||)
