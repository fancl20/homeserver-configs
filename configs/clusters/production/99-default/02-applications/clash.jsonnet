local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('clash')
.PodContainers([{
  image: images.clash,
  command: ['/bin/bash', '-ex', '-c', |||
    cat /etc/config/config.yaml <(echo) /vault/secrets/proxies > /root/.config/clash/config.yaml

    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun

    ip route replace 10.96.0.0/12 via 10.244.0.1 # serviceCIDR
    ip route replace default via 192.168.1.1 dev net1

    exec /opt/bin/clash
  |||],
  securityContext: {
    capabilities: { add: ['NET_ADMIN', 'SYS_MODULE', 'SYS_ADMIN'] },
  },
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
  ],
  volumeMounts: [
    { name: 'config', mountPath: '/etc/config' },
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
  { name: 'config', configMap: { name: 'clash' } },
])
.VaultInjector('proxy', {
  proxies: {
    path: 'homeserver/data/clash',
    template: |||
      {{ with secret "homeserver/data/clash" -}}
      {{ .Data.data.proxies }}
      {{- end }}
    |||,
  },
})
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 9090 },
  ],
})
.Ingress()
.Kustomize()
.Config('config.yaml', std.manifestYamlDoc({
  'external-controller': '0.0.0.0:9090',
  'external-ui': 'clash-dashboard-gh-pages',

  'interface-name': 'net1',

  ipv6: false,
  tun: { enable: true, stack: 'system' },

  'routing-mark': 1,
  ebpf: { 'redirect-to-tun': ['net1'] },

  dns: {
    enable: true,
    listen: '0.0.0.0:53',
    'enhanced-mode': 'fake-ip',
    'fake-ip-range': '198.18.0.0/16',
    'fake-ip-filter': [
      'time.windows.com',
      '+.playstation.*',
      '+.local.d20.fan',
    ],
    nameserver: ['udp://192.168.1.1:53'],
  },

  mode: 'Rule',

  script: {
    engine: 'expr',
    shortcuts: {
      genshin: 'network == "udp" and dst_port in [22101, 22102]',
      mihoyo: 'host in ["log-upload.mihoyo.com", "sdk-static.mihoyo.com", "hk4e-sdk.mihoyo.com"]',
    },
  },

  rules: [
    'SCRIPT,genshin,SG1-SG2-CN2',
    'SCRIPT,mihoyo,JP2',
    'GEOIP,CN,JP2',
    'MATCH,DIRECT',
  ],
}))
