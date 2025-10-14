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
      { name: 'coder-db', mountPath: '/var/lib/postgresql' },
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
    apiVersion: 'v1',
    kind: 'Namespace',
    metadata: {
      name: 'coder',
    },
  },

  'helmrepository.yaml': {
    apiVersion: 'source.toolkit.fluxcd.io/v1',
    kind: 'HelmRepository',
    metadata: {
      name: 'coder',
      namespace: 'coder',
    },
    spec: {
      interval: '1h0s',
      url: 'https://helm.coder.com/v2',
    },
  },

  'helmrelease.yaml': {
    apiVersion: 'helm.toolkit.fluxcd.io/v2',
    kind: 'HelmRelease',
    metadata: {
      name: 'coder',
      namespace: 'coder',
    },
    spec: {
      interval: '15m',
      chart: {
        spec: {
          chart: 'coder',
          sourceRef: { kind: 'HelmRepository', name: 'coder' },
        },
      },
      values: {
        local domain = 'coder.local.d20.fan',
        coder: {
          env: [
            { name: 'CODER_PG_CONNECTION_URL', valueFrom: { secretKeyRef: { name: 'coder-db', key: 'url' } } },
            { name: 'CODER_ACCESS_URL', value: 'https://' + domain },
          ],
          ingress: {
            enable: true,
            host: domain,
            tls: { enable: true },
          },
        },
      },
    },
  },
}
