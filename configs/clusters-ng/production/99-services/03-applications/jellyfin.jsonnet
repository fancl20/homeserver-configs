local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('jellyfin').Deployment()
.PodContainers([{
  image: images.jellyfin,
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
    { name: 'PUID', value: '1000' },
    { name: 'PGID', value: '1000' },
  ],
  volumeMounts: [
    { name: 'jellyfin', mountPath: '/config'},
    { name: 'data', mountPath: '/shared'},
  ],
}])
.PodVolumes([
  app.Volumes.shared_data,
])
.PersistentVolumeClaim()
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 8096 },
  ],
})
.HTTPRoute()
