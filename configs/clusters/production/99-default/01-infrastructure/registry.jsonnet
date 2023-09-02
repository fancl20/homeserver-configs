local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('registry')
.PodContainers([{
  image: images.registry,
  volumeMounts: [
    { name: 'data', mountPath: '/var/lib/registry', subPath: 'registry' },
  ],
}])
.PodVolumes([
  app.Volumes.mass_storage,
])
.Service({
  ports: [
    { name: 'http', protocol: 'TCP', port: 80, targetPort: 5000 },
  ],
})
.Ingress()
