local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('fava').Deployment()
.PodContainers([{
  image: images.fava,
  command: ['/usr/local/bin/fava', '--port', '5000', '/workspace/main.beancount'],
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
  ],
  volumeMounts: [
    { name: 'fava', mountPath: '/workspace' },
  ],
}])
.PersistentVolumeClaim()
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 5000 },
    { name: 'ssh', protocol: 'TCP', port: 22, targetPort: 2222 },
  ],
})
.HTTPRoute()
