local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('fava')
.PodContainers([{
  image: images.fava,
  command: ['/usr/local/bin/fava', '--port', '5000', '/data/main.beancount'],
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
  ],
  volumeMounts: [
    { name: 'data', mountPath: '/data', subPath: 'workspaces/common/accounting' },
  ],
}])
.PodVolumes([
  app.Volumes.mass_storage,
])
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 5000 },
  ],
})
.Ingress()
