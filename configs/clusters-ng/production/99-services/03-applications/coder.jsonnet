local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('coder-db', 'coder')
.StatefulSet()
.PodContainers([
  {
    name: 'postgres',
    image: images.postgres,
    envFrom: [
      { secretRef: { name: 'coder-db' } },
    ],
    volumeMounts: [
      { name: 'coder-db', mountPath: '/var/lib/postgresql/data' },
    ],
  },
])
.PersistentVolumeClaim()
.Service({
  ports: [
    { name: 'postgres', protocol: 'TCP', port: 5432, targetPort: 5432 },
  ],
}) + {
  'namespace.yaml': {
    'apiVersion': 'v1',
    'kind': 'Namespace',
    'metadata': {
      'name': 'coder',
    },
  },
}
