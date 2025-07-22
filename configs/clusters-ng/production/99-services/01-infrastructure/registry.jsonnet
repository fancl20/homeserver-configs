local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('registry')
.PodContainers([{
  image: images.registry,
  env: [
    { name: 'OTEL_TRACES_EXPORTER', value: 'none' },
  ],
  volumeMounts: [
    { name: 'registry', mountPath: '/var/lib/registry'},
  ],
}])
.PersistentVolumeClaim()
.Service({
  ports: [
    { name: 'http', protocol: 'TCP', port: 80, targetPort: 5000 },
  ],
})
.Ingress()
