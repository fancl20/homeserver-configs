local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('image-controller', 'continuous', create_namespace={
  labels: {
    'pod-security.kubernetes.io/enforce': 'privileged',
    'pod-security.kubernetes.io/warn': 'privileged',
    'pod-security.kubernetes.io/audit': 'privileged',
  },
})
.Deployment()
.PodContainers([{
  image: images['image-controller'],
  ports: [{
    name: 'healthz',
    containerPort: 8081,
  }],
  livenessProbe: {
    httpGet: { path: '/healthz', port: 'healthz' },
  },
  readinessProbe: {
    httpGet: { path: '/readyz', port: 'healthz' },
  },
  securityContext: {
    allowPrivilegeEscalation: false,
    readOnlyRootFilesystem: true,
    capabilities: { drop: ['ALL'] },
  },
}])
.PodSecurityContext({
  runAsNonRoot: true,
  seccompProfile: { type: 'RuntimeDefault' },
})
.ClusterRole(rules=[
  {
    apiGroups: ['d20.fan'],
    resources: ['containerimages'],
    verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete'],
  },
  {
    apiGroups: ['d20.fan'],
    resources: ['containerimages/status', 'containerimages/finalizers'],
    verbs: ['get', 'update', 'patch'],
  },
  {
    apiGroups: ['source.toolkit.fluxcd.io'],
    resources: ['gitrepositories'],
    verbs: ['get', 'list', 'watch'],
  },
  {
    apiGroups: ['image.toolkit.fluxcd.io'],
    resources: ['imagepolicies'],
    verbs: ['get', 'list', 'watch'],
  },
  {
    apiGroups: ['', 'events.k8s.io'],
    resources: ['events'],
    verbs: ['create', 'patch'],
  },
])
.Role(name='image-controller', rules=[
  {
    apiGroups: ['batch'],
    resources: ['jobs'],
    verbs: ['get', 'list', 'watch', 'create', 'delete', 'deletecollection'],
  },
  {
    apiGroups: [''],
    resources: ['pods'],
    verbs: ['get', 'list', 'watch'],
  },
])
+ {
  // Open source-controller's artifact API to the build namespace. The stock
  // Flux NetworkPolicies only allow same-namespace ingress (plus 8080/9292).
  'networkpolicy_allow-source-controller-artifacts.yaml': {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: {
      name: 'allow-source-controller-artifacts',
      namespace: 'flux-system',
    },
    spec: {
      podSelector: {
        matchLabels: { app: 'source-controller' },
      },
      policyTypes: ['Ingress'],
      ingress: [{
        from: [{
          namespaceSelector: {
            matchLabels: { 'kubernetes.io/metadata.name': 'continuous' },
          },
        }],
        ports: [{ protocol: 'TCP', port: 'http' }],
      }],
    },
  },
}
