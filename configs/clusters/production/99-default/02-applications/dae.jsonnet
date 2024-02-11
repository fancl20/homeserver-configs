local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('dae')
.PodContainers([{
  image: images.dae,
  command: ['/bin/bash', '-ex', '-c', |||
    mount bpffs /sys/fs/bpf/ -t bpf

    ip route replace 10.96.0.0/12 via 10.244.0.1 # serviceCIDR
    ip route replace default via 192.168.1.1 dev net1

    exec /opt/dae/daed run
  |||],
  securityContext: {
    capabilities: { add: ['NET_ADMIN', 'SYS_MODULE', 'SYS_ADMIN'] },
  },
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
  ],
  volumeMounts: [
    { name: 'data', mountPath: '/etc/daed', subPath: 'dae/config' },
  ],
}])
.PodAnnotations({
  'k8s.v1.cni.cncf.io/networks': std.manifestJson([
    {
      name: 'macvlan',
      ips: ['192.168.1.246/24'],
      mac: '26:1e:94:c2:23:41',
      gateway: ['192.168.1.1'],
    },
  ]),
})
.PodSecurityContext({
  sysctls: [
    { name: 'net.ipv4.conf.net1.forwarding', value: '1' },
    { name: 'net.ipv6.conf.net1.forwarding', value: '1' },
    { name: 'net.ipv4.conf.net1.send_redirects', value: '0' },
    { name: 'net.ipv4.ip_forward', value: '1' },
  ],
})
.PodVolumes([
  app.Volumes.mass_storage,
])
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 2023 },
  ],
})
.Ingress()
