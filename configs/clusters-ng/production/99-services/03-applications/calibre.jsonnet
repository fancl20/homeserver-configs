local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('calibre').Deployment()
.PodContainers([{
  image: images.calibre,
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
    { name: 'PUID', value: '1000' },
    { name: 'PGID', value: '1000' },
  ],
  volumeMounts: [
    { name: 'calibre', mountPath: '/config'},
    { name: 'data', mountPath: '/books', subPath: 'calibre'},
  ],
}])
.PodVolumes([
  app.Volumes.shared_data,
])
.PersistentVolumeClaim()
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 8083 },
  ],
})
.HTTPRoute()
