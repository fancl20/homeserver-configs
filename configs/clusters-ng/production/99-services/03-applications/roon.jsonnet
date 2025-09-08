local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('roon-server')
.PodContainers([{
  image: images.roon,
  command: ['/bin/bash', '-ex', '-c', |||
    ip route replace 10.96.0.0/12 via 10.244.0.1 dev eth0 onlink # serviceCIDR
    ip route replace default via 192.168.1.1 dev net1

    exec /app/RoonServer/start.sh
  |||],
  securityContext: {
    capabilities: { add: ['NET_ADMIN'] },
  },
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
  ],
  volumeMounts: [
    { name: 'roon-server', mountPath: '/data', subPath: 'data' },
    { name: 'roon-server', mountPath: '/backup', subPath: 'backup' },
    { name: 'data', mountPath: '/music', subPath: 'music' },
  ],
}])
.PodVolumes([
  app.Volumes.shared_data,
])
.PersistentVolumeClaim()
.PodAnnotations({
  'k8s.v1.cni.cncf.io/networks': std.manifestJson([
    {
      name: 'macvlan',
      ips: ['192.168.1.31/24'],
    },
  ]),
})
