local app = import 'app.libsonnet';

app.Base('beets')
.PodContainers([{
  image: 'lscr.io/linuxserver/beets',
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
    { name: 'DOCKER_MODS', value: 'ghcr.io/fancl20/beets-shntool:latest' },
  ],
  volumeMounts: [
    { name: 'data', mountPath: '/config', subPath: 'beets/config' },
    { name: 'data', mountPath: '/music', subPath: 'shared/music' },
    { name: 'data', mountPath: '/downloads', subPath: 'shared/downloads' },
  ],
}])
.PodVolumes([
  app.Volumes.mass_storage,
])
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 8337 },
  ],
})
.Ingress()
