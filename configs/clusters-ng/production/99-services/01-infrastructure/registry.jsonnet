local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('registry').Deployment()
.PodContainers([{
  image: images.registry,
  env: [
    { name: 'OTEL_TRACES_EXPORTER', value: 'none' },
    { name: 'REGISTRY_LOG_LEVEL', value: 'info' },
  ],
  volumeMounts: [
    { name: 'registry', mountPath: '/var/lib/registry' },
  ],
}])
.RunAsUser()
.PersistentVolumeClaim(spec={
  resources: {
    requests: { storage: '32Gi' },
  },
})
.Service({
  ports: [
    { name: 'http', protocol: 'TCP', port: 80, targetPort: 5000 },
  ],
})
.Ingress()
