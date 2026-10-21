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
  // Signal shim until v1.38: forwards the pod's SIGTERM to coder as SIGINT,
  // which takes the cancel-jobs shutdown path (5s) instead of waiting for
  // in-flight provisioner jobs. Once ContainerStopSignals reaches beta in
  // v1.38 the stopSignal fields apply directly — remove this shim and restore
  // the 60s termination grace period then.
  command: [
    '/bin/sh',
    '-ec',
    |||
      /opt/coder server &
      child=$!
      trap 'kill -INT "$child"' TERM INT
      while kill -0 "$child" 2>/dev/null; do
        wait "$child" || :
      done
    |||,
  ],
  stopSignal: 'SIGINT',
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
      token_file=/var/run/coder-init-token/token

      # Read the session token from the mounted coder-init-token secret; the
      # output is empty while the secret does not exist. Re-reading on every
      # use picks up a token placed in the secret without a pod restart.
      read_token() {
        cat "${token_file}" 2>/dev/null || true
      }

      until curl -sSf http://127.0.0.1:8080/healthz; do
        echo "Waiting for Coder to be ready..."
        sleep 5
      done

      export CODER_SESSION_TOKEN=$(read_token)
      login_failed=""

      trap "exit" TERM
      while :; do
        if [[ -z "${CODER_SESSION_TOKEN}" ]]; then
          first_user=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/api/v2/users/first || true)
          if [[ "${first_user}" == 404 ]]; then
            echo "Initializing Coder with first user..."
            coder login --use-token-as-session || echo "First user setup failed, retrying..."
          fi
          token=$(read_token)
          if [[ -n "${token}" && "${token}" != "${login_failed}" ]]; then
            echo "Using session token from the coder-init-token secret..."
            export CODER_SESSION_TOKEN=${token}
          elif [[ "${first_user}" == 200 && -z "${token}" ]]; then
            echo "Waiting for a session token in the coder-init-token secret..."
            sleep 5
            continue
          fi
        fi

        if [[ -n "${CODER_SESSION_TOKEN}" ]]; then
          expire=$(date -d "$( (coder token view ${CODER_SESSION_TOKEN} -c "expires at" || date -I) | tail -n 1 | cut -d"T" -f1)" "+%s")
          ttl=$(expr "${expire}" - $(date "+%s"))
          # Recheck hourly; the 3d threshold is days away and re-reading the
          # secret picks up externally patched tokens at the same cadence as
          # the ExternalSecret sync.
          if [[ "${ttl}" -gt 259200 ]]; then
            echo "Token ttl: ${ttl} greater than 259200, sleeping 3600..."
            sleep 3600
            continue
          fi
          echo "Token ttl: ${ttl} less than 259200, refreshing..."
        else
          echo "Minting the initial session token..."
        fi

        if ! token=$(coder token create --lifetime 7d); then
          if ! curl -sSf http://127.0.0.1:8080/healthz > /dev/null; then
            echo "Coder is not ready, retrying..."
            sleep 5
            continue
          fi
          if coder token view ${CODER_SESSION_TOKEN} -c "expires at" > /dev/null 2>&1; then
            echo "Token refresh failed, retrying..."
            sleep 60
            continue
          fi
          echo "Session token is invalid, waiting for a new token in the coder-init-token secret..."
          login_failed=${CODER_SESSION_TOKEN}
          unset CODER_SESSION_TOKEN
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
        if [[ ! -f "${token_file}" ]]; then
          method="POST"
          url_suffix=""
        fi
        if ! curl -sSf --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -X ${method} \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
          -d "${data}" \
          https://kubernetes.default.svc/api/v1/namespaces/coder/secrets/${url_suffix} > /dev/null; then
          echo "Failed to update the coder-init-token secret, retrying..."
          continue
        fi

        export CODER_SESSION_TOKEN=${token}
        sleep 60
      done
    |||,
  ],
  env: [
    { name: 'CODER_URL', value: 'http://127.0.0.1:8080/' },
    { name: 'CODER_FIRST_USER_USERNAME', value: 'fancl20' },
    { name: 'CODER_FIRST_USER_FULL_NAME', value: 'fancl20' },
    { name: 'CODER_FIRST_USER_EMAIL', valueFrom: { secretKeyRef: { name: 'coder', key: 'username' } } },
    { name: 'CODER_FIRST_USER_PASSWORD', valueFrom: { secretKeyRef: { name: 'coder', key: 'password' } } },
  ],
  volumeMounts: [
    { name: 'coder-init-token', mountPath: '/var/run/coder-init-token', readOnly: true },
  ],
}, {
  name: 'postgres',
  image: images.postgres,
  restartPolicy: 'Always',
  stopSignal: 'SIGINT',
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
.PodSpec({ terminationGracePeriodSeconds: 120 })
.PodVolumes([{
  name: 'coder-init-token',
  secret: { secretName: 'coder-init-token', optional: true },
}])
// Permissions for the workspace provisioner: the embedded provisioner runs
// Terraform in-cluster as this pod's service account and creates workspace
// pods, PVCs, and deployments in this namespace.
.Role(name='coder-workspace', rules=[{
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
.ClusterRole(rules=[{
  apiGroups: ['image.toolkit.fluxcd.io'],
  resources: ['imagepolicies'],
  verbs: ['get', 'list', 'watch'],
}])
.PersistentVolumeClaim('coder-db', {
  accessModes: ['ReadWriteOnce'],
  storageClassName: 'rook-rbd',
})
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
