local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('roon-server')
.PodContainers([{
  image: images.roon,
  command: ['/bin/bash', '-ex', '-c', |||
    ip route replace 10.96.0.0/12 via 10.244.0.1 # serviceCIDR
    ip route replace default via 192.168.1.1 dev net1

    exec /app/RoonServer/start.sh
  |||],
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
  ],
  volumeMounts: [
    { name: 'data', mountPath: '/data', subPath: 'roon-server/data' },
    { name: 'data', mountPath: '/backup', subPath: 'roon-server/backup' },
    { name: 'data', mountPath: '/music', subPath: 'shared/music' },
  ],
}])
.PodVolumes([
  app.Volumes.mass_storage,
])
.PodAnnotations({
  'k8s.v1.cni.cncf.io/networks': std.manifestJson([
    {
      name: 'macvlan',
      ips: ['192.168.1.244/24'],
      mac: '26:1e:94:c2:23:39',
      gateway: ['192.168.1.1'],
    },
  ]),
})
