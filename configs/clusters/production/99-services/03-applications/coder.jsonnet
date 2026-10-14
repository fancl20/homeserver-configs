local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('coder', 'coder', create_namespace={
  labels: {
    'pod-security.kubernetes.io/enforce': 'privileged',
    'pod-security.kubernetes.io/audit': 'privileged',
    'pod-security.kubernetes.io/warn': 'privileged',
  },
}).Deployment()
.PodContainers([{
  image: images.coder,
  command: ['/opt/coder'],
  args: ['server'],
  env: [
    { name: 'KUBE_POD_IP', valueFrom: { fieldRef: { fieldPath: 'status.podIP' } } },
    { name: 'CODER_HTTP_ADDRESS', value: '0.0.0.0:8080' },
    { name: 'CODER_PG_CONNECTION_URL', valueFrom: { secretKeyRef: { name: 'coder-db', key: 'url' } } },
    { name: 'CODER_ACCESS_URL', value: 'https://coder.local.d20.fan' },
    { name: 'CODER_WILDCARD_ACCESS_URL', value: '*.coder.local.d20.fan' },
    { name: 'CODER_DERP_SERVER_RELAY_URL', value: 'http://$(KUBE_POD_IP):8080' },
    { name: 'CODER_CLUSTER_HOST', value: '$(KUBE_POD_IP)' },
  ],
  ports: [
    { name: 'http', containerPort: 8080, protocol: 'TCP' },
  ],
  readinessProbe: {
    httpGet: { path: '/healthz', port: 'http' },
  },
  resources: {
    requests: { memory: '1024Mi' },
  },
  securityContext: {
    runAsNonRoot: true,
    runAsUser: 1000,
    runAsGroup: 1000,
    seccompProfile: { type: 'RuntimeDefault' },
    allowPrivilegeEscalation: false,
  },
}])
.PodInitContainers([{
  name: 'coder-init',
  image: images.coder,
  restartPolicy: 'Always',
  command: [
    '/bin/sh',
    '-ec',
    |||
      until curl -sSf http://127.0.0.1:8080/healthz; do
        echo "Waiting for Coder to be ready..."
        sleep 5
      done

      echo "Initializing Coder with first user..."
      coder login --use-token-as-session

      trap "exit" TERM
      while sleep 60; do
        expire=$(date -d "$( (coder token view ${CODER_SESSION_TOKEN} -c "expires at" || date -I) | tail -n 1 | cut -d"T" -f1)" "+%s")
        ttl=$(expr "${expire}" - $(date "+%s"))
        if [[ "${ttl}" -gt 259200 ]]; then
          echo "Token ttl: ${ttl} greater than 259200, continue..."
          continue
        fi
        echo "Token ttl: ${ttl} less than 259200, refreshing..."

        token=$(coder token create --lifetime 7d)
        if [[ -z ${token} ]]; then
          echo "Failed to create new token, continue..."
          continue
        fi

        echo "Update secrets for the new token..."
        data='{
          "kind": "Secret",
          "apiVersion": "v1",
          "metadata": {
            "name": "coder-init-token",
            "namespace": "coder"
          },
          "type": "Opaque",
          "data": {
            "token": "'$(echo -n ${token} | base64)'"
          }
        }'
        method="PUT"
        url_suffix="coder-init-token"
        if [[ -z ${CODER_SESSION_TOKEN} ]]; then
          method="POST"
          url_suffix=""
        fi
        curl -sSf --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -X ${method} \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
          -d "${data}" \
          https://kubernetes.default.svc/api/v1/namespaces/coder/secrets/${url_suffix} > /dev/null

        echo "Login with the new session token..."
        export CODER_SESSION_TOKEN=${token}
        coder login --use-token-as-session
      done
    |||,
  ],
  env: [
    { name: 'CODER_URL', value: 'http://127.0.0.1:8080/' },
    { name: 'CODER_FIRST_USER_USERNAME', value: 'fancl20' },
    { name: 'CODER_FIRST_USER_EMAIL', valueFrom: { secretKeyRef: { name: 'coder', key: 'username' } } },
    { name: 'CODER_FIRST_USER_PASSWORD', valueFrom: { secretKeyRef: { name: 'coder', key: 'password' } } },
    { name: 'CODER_SESSION_TOKEN', valueFrom: { secretKeyRef: { name: 'coder-init-token', key: 'token', optional: true } } },
  ],
}, {
  name: 'postgres',
  image: images.postgres,
  restartPolicy: 'Always',
  envFrom: [
    { secretRef: { name: 'coder-db' } },
  ],
  resources: {
    requests: { memory: '512Mi' },
  },
  volumeMounts: [
    { name: 'coder-db', mountPath: '/var/lib/postgresql' },
  ],
}])
.PodSpec({ terminationGracePeriodSeconds: 60 })
// Permissions for the workspace provisioner: the embedded provisioner runs
// Terraform in-cluster as this pod's service account and creates workspace
// pods, PVCs, and deployments in this namespace.
.Role(name='coder-workspace-perms', rules=[{
  apiGroups: [''],
  resources: ['pods', 'persistentvolumeclaims'],
  verbs: ['create', 'delete', 'deletecollection', 'get', 'list', 'patch', 'update', 'watch'],
}, {
  apiGroups: ['apps'],
  resources: ['deployments'],
  verbs: ['create', 'delete', 'deletecollection', 'get', 'list', 'patch', 'update', 'watch'],
}])
.Role(name='coder-init', rules=[{
  apiGroups: [''],
  resources: ['secrets'],
  verbs: ['create', 'update'],
}])
.PersistentVolumeClaim('coder-db')
.Service({
  ports: [
    { name: 'http', protocol: 'TCP', port: 80, targetPort: 8080 },
  ],
})
.HTTPRoute(wildcard=true)
.OnePassword(spec={
  dataFrom: [
    { extract: { key: 'Coder' } },
  ],
})
.OnePassword(name='fancl20', spec={
  dataFrom: [
    { extract: { key: 'Coder Workspace' } },
  ],
})
