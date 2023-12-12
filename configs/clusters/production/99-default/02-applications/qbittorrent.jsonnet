local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('qbittorrent')
.PodContainers([{
  image: images.qbittorrent,
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
    { name: 'PUID', value: '0' },
    { name: 'GUID', value: '0' },
  ],
  volumeMounts: [
    { name: 'data', mountPath: '/config', subPath: 'qbittorrent/config' },
    { name: 'data', mountPath: '/downloads', subPath: 'shared/downloads' },
  ],
}])
.PodVolumes([
  app.Volumes.mass_storage,
])
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 8080 },
  ],
}, service_name='qbittorrent-ui')
.Service({
  name: 'qbittorrent-p2p',
  ports: [
    { name: 'tcp', protocol: 'TCP', port: 6881, targetPort: 6881 },
    { name: 'udp', protocol: 'UDP', port: 6881, targetPort: 6881 },
  ],
}, service_name='qbittorrent-p2p')
.Ingress(service='qbittorrent-ui')
