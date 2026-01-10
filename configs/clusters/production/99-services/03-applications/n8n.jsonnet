local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('n8n').Deployment()
.PodContainers([
  {
    image: images.n8n,
    env: [
      { name: 'N8N_PROTOCOL', value: 'http' },
      { name: 'N8N_PORT', value: '5678' },
    ],
    volumeMounts: [
      { name: 'n8n', mountPath: '/home/node/.n8n' },
    ],
  },
])
.RunAsUser()
.PersistentVolumeClaim()
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 5678 },
  ],
})
.HTTPRoute()
