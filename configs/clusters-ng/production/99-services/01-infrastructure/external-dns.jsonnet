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
    '--rfc2136-tsig-keyname=bind9-externaldns',
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
.RunAsUser()
.ClusterRole([{
  apiGroups: [''],
  resources: ['services', 'pods'],
  verbs: ['get', 'watch', 'list'],
}, {
  apiGroups: ['discovery.k8s.io'],
  resources: ['endpointslices'],
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

