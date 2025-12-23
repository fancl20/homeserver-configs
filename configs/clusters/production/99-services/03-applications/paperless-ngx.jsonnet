local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('paperless').Deployment()
.PodContainers([{
  image: images['paperless-ngx'],
  env: [
    { name: 'PAPERLESS_REDIS', value: 'redis://localhost:6379' },
    { name: 'PAPERLESS_URL', value: 'https://paperless.local.d20.fan' },
    { name: 'PAPERLESS_TIME_ZONE', value: 'Australia/Sydney' },
    { name: 'USERMAP_UID', value: '1000' },
    { name: 'USERMAP_GID', value: '1000' },
  ],
  volumeMounts: [
    { name: 'paperless', mountPath: '/usr/src/paperless/data', subPath: 'paperless/data' },
    { name: 'paperless', mountPath: '/usr/src/paperless/media', subPath: 'paperless/media' },
    { name: 'paperless', mountPath: '/usr/src/paperless/export', subPath: 'paperless/export' },
    { name: 'paperless', mountPath: '/usr/src/paperless/consume', subPath: 'paperless/consume' },
  ],
}, {
  name: 'redis',
  image: images.redis,
  volumeMounts: [
    { name: 'paperless', mountPath: '/data', subPath: 'redis/data' },
  ],
}])
.PersistentVolumeClaim()
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 8000 },
  ],
})
.HTTPRoute()
