local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('beets').Deployment()
.PodContainers([{
  image: images.beets,
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
    { name: 'PUID', value: '1000' },
    { name: 'PGID', value: '1000' },
  ],
  volumeMounts: [
    { name: 'beets', mountPath: '/config' },
    { name: 'data', mountPath: '/music', subPath: 'music' },
    { name: 'data', mountPath: '/downloads', subPath: 'downloads' },
  ],
}])
.PodVolumes([
  app.Volumes.shared_data,
])
.PersistentVolumeClaim()
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 8337 },
  ],
})
.Ingress()
