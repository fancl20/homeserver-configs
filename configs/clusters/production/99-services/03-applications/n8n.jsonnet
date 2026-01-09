local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('n8n').StatefulSet()
.PodContainers([
  {
    image: images.n8n,
    command: ['/bin/sh'],
    args: ['-c', 'sleep 5; n8n start'],
    env: [
      { name: 'DB_TYPE', value: 'postgresdb' },
      { name: 'DB_POSTGRESDB_HOST', value: '127.0.0.1' },
      { name: 'DB_POSTGRESDB_PORT', value: '5432' },
      { name: 'DB_POSTGRESDB_DATABASE', value: 'n8n' },
      { name: 'N8N_PROTOCOL', value: 'http' },
      { name: 'N8N_PORT', value: '5678' },
    ],
    envFrom: [
      { secretRef: { name: 'n8n' } },
    ],
    volumeMounts: [
      { name: 'n8n', mountPath: '/home/node/.n8n', subPath: 'n8n' },
    ],
  },
  {
    name: 'postgres',
    image: images.postgres,
    env: [
      { name: 'PGDATA', value: '/var/lib/postgresql/data/pgdata' },
      { name: 'POSTGRES_DB', value: 'n8n' },
    ],
    envFrom: [
      { secretRef: { name: 'n8n' } },
    ],
    volumeMounts: [
      { name: 'n8n', mountPath: '/var/lib/postgresql/data', subPath: 'db' },
    ],
  },
])
.RunAsUser()
.PersistentVolumeClaim()
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 5678, targetPort: 5678 },
  ],
})
.HTTPRoute()
