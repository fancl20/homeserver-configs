local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('calibre')
.PodContainers([{
  image: images.calibre,
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
    { name: 'PUID', value: '0' },
    { name: 'GUID', value: '0' },
    { name: 'DOCKER_MODS', value: 'linuxserver/mods:universal-calibre:latest' },
  ],
  volumeMounts: [
    { name: 'data', mountPath: '/config', subPath: 'calibre/config' },
    { name: 'data', mountPath: '/books', subPath: 'shared/calibre' },
  ],
}])
.PodVolumes([
  app.Volumes.mass_storage,
])
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 8083 },
  ],
})
.Ingress()
