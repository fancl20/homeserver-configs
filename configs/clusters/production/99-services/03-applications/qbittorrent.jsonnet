local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('qbittorrent').Deployment()
.PodContainers([{
  image: images.qbittorrent,
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
    { name: 'PUID', value: '1000' },
    { name: 'PGID', value: '1000' },
  ],
  volumeMounts: [
    { name: 'qbittorrent', mountPath: '/config' },
    { name: 'data', mountPath: '/downloads', subPath: 'downloads' },
  ],
}])
.PodVolumes([
  app.Volumes.shared_data,
])
.PersistentVolumeClaim()
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 8080 },
  ],
}, name='qbittorrent-ui')
.Service({
  name: 'qbittorrent-p2p',
  ports: [
    { name: 'tcp', protocol: 'TCP', port: 6881, targetPort: 6881 },
    { name: 'udp', protocol: 'UDP', port: 6881, targetPort: 6881 },
  ],
}, name='qbittorrent-p2p')
.HTTPRoute(service='qbittorrent-ui')
