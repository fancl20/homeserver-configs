local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('external-dns')
.PodContainers([{
  image: images['external-dns'],
  command: ['/bin/sh', '-e', '-c', |||
    source /vault/secrets/env && exec /bin/external-dns \
      --registry=txt \
      --txt-prefix=external-dns- \
      --txt-owner-id=k8s \
      --provider=rfc2136 \
      --rfc2136-host=bind9.default \
      --rfc2136-port=53 \
      --rfc2136-zone=local.d20.fan \
      --rfc2136-tsig-keyname=externaldns-key \
      --rfc2136-tsig-axfr \
      --source=service \
      --source=ingress \
      --domain-filter=local.d20.fan
  |||],
  resources: {
    requests: { memory: '32Mi', cpu: '100m' },
    limits: { memory: '64Mi', cpu: '200m' },
  },
}])
.VaultInjector('external_dns', {
  bind9_externaldns_key: {
    path: 'homeserver/data/bind9',
    template: |||
      {{ with secret "homeserver/data/bind9" -}}
      export EXTERNAL_DNS_RFC2136_TSIG_SECRET="{{ .Data.data.externaldns_key_secret }}"
      export EXTERNAL_DNS_RFC2136_TSIG_SECRET_ALG="{{ .Data.data.externaldns_key_algorithm }}"
      {{- end }}
    |||,
  },
})
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
