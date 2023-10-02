local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('jellyfin')
.PodContainers([{
  image: images.jellyfin,
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
    { name: 'PUID', value: '0' },
    { name: 'GUID', value: '0' },
  ],
  volumeMounts: [
    { name: 'data', mountPath: '/config', subPath: 'jellyfin/config' },
    { name: 'data', mountPath: '/shared', subPath: 'shared' },
  ],
}])
.PodVolumes([
  app.Volumes.mass_storage,
])
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 8096 },
  ],
})
.Ingress()
