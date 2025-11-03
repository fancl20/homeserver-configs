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
})
.OnePassword(secret_name='coder', spec={
  dataFrom: [
    { extract: { key: 'Coder' } },
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
          initContainers: [{
            name: 'coder-init',
            image: 'ghcr.io/coder/coder:latest',
            restartPolicy: 'Always',
            command: [
              '/bin/sh', '-exc', |||
                until curl -f http://127.0.0.1:8080/healthz; do
                  echo "Waiting for Coder to be ready..."
                  sleep 5
                done

                echo "Initializing Coder with first user..."
                coder login \
                  --first-user-username fancl20 \
                  --first-user-email "$CODER_USER_EMAIL" \
                  --first-user-password "$CODER_USER_PASSWORD" \
                  --use-token-as-session \
                  http://127.0.0.1:8080/

                exec sleep infinity
              |||
            ],
            env: [
              { name: 'CODER_USER_EMAIL', valueFrom: { secretKeyRef: { name: 'coder', key: 'username' } } },
              { name: 'CODER_USER_PASSWORD', valueFrom: { secretKeyRef: { name: 'coder', key: 'password' } } },
            ],
          }],
        },
      },
    },
  },
}
