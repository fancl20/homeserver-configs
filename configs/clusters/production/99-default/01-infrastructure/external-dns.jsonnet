local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('external-dns')
.PodContainers([{
  image: images['external-dns'],
  args: [
    '--registry=txt',
    '--txt-prefix=external-dns-',
    '--txt-owner-id=k8s',
    '--provider=rfc2136',
    '--rfc2136-host=bind9.default',
    '--rfc2136-port=53',
    '--rfc2136-zone=local.d20.fan',
    '--rfc2136-tsig-keyname=externaldns-key',
    '--rfc2136-tsig-axfr',
    '--source=service',
    '--source=ingress',
    '--domain-filter=local.d20.fan',
  ],
  envFrom: [
    { secretRef: { name: 'external-dns' } },
  ],
  resources: {
    requests: { memory: '32Mi', cpu: '100m' },
    limits: { memory: '64Mi', cpu: '200m' },
  },
}])
.ClusterRole([{
  apiGroups: [''],
  resources: ['services', 'endpoints', 'pods'],
  verbs: ['get', 'watch', 'list'],
}, {
  apiGroups: ['extensions', 'networking.k8s.io'],
  resources: ['ingresses'],
  verbs: ['get', 'watch', 'list'],
}, {
  apiGroups: [''],
  resources: ['nodes'],
  verbs: ['list', 'watch'],
}])
.ClusterRoleBinding()
+ {
  'secretstore.yaml': {
    apiVersion: 'external-secrets.io/v1beta1',
    kind: 'SecretStore',
    metadata: {
      name: 'external-dns',
      namespace: 'default',
    },
    spec: {
      provider: {
        vault: {
          server: 'http://vault.vault.svc:8200/',
          path: 'homeserver',
          auth: {
            kubernetes: {
              mountPath: 'kubernetes',
              role: 'external_dns',
              serviceAccountRef: { name: 'external-dns' },
            },
          },
        },
      },
    },
  },
  'externalsecret.yaml': {
    apiVersion: 'external-secrets.io/v1beta1',
    kind: 'ExternalSecret',
    metadata: {
      name: 'external-dns',
      namespace: 'default',
    },
    spec: {
      refreshInterval: '1m',
      secretStoreRef: {
        name: 'external-dns',
        kind: 'SecretStore',
      },
      target: {
        name: 'external-dns',
        creationPolicy: 'Owner',
      },
      dataFrom: [{
        extract: { key: 'bind9' },
        rewrite: [
          { regexp: { source: 'externaldns_key_secret', target: 'EXTERNAL_DNS_RFC2136_TSIG_SECRET' } },
          { regexp: { source: 'externaldns_key_algorithm', target: 'EXTERNAL_DNS_RFC2136_TSIG_SECRET_ALG' } },
        ],
      }],
    },
  },
}
