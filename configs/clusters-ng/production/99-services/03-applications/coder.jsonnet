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

  'role.yaml': {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'Role',
    metadata: {
      name: 'coder-init',
      namespace: 'coder',
    },
    rules: [{
      apiGroups: [""],
      resources: ["secrets"],
      verbs: ["create", "update"],
    }],
  },

  'rolebinding.yaml': {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'RoleBinding',
    metadata: {
      name: 'coder-init',
      namespace: 'coder',
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'Role',
      name: 'coder-init',
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: 'coder',
      namespace: 'coder',
    }],
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
      annotations: { 'kustomize.toolkit.fluxcd.io/substitute': 'disabled' },
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
          resources: {
            requests: { memory: '1024Mi' },
          },
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
              '/bin/sh', '-ec', |||
                until curl -sSf http://127.0.0.1:8080/healthz; do
                  echo "Waiting for Coder to be ready..."
                  sleep 5
                done

                echo "Initializing Coder with first user..."
                coder login --use-token-as-session

                trap "exit" TERM
                while sleep 60; do
                  expire=$(date -d $(coder token view ${CODER_SESSION_TOKEN} -c "expires at" | tail -n 1 | cut -d"T" -f1) "+%s")
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
                  method=$([[ -z ${CODER_SESSION_TOKEN} ]] && echo -n POST || echo -n PUT)
                  curl -sSf --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -X ${method} \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
                    -d "${data}" \
                    https://kubernetes.default.svc/api/v1/namespaces/coder/secrets/coder-init-token > /dev/null

                  echo "Login with the new session token..."
                  export CODER_SESSION_TOKEN=${token}
                  coder login --use-token-as-session
                done
              |||
            ],
            env: [
              { name: 'CODER_URL', value: 'http://127.0.0.1:8080/' },
              { name: 'CODER_FIRST_USER_USERNAME', value: 'fancl20' },
              { name: 'CODER_FIRST_USER_EMAIL', valueFrom: { secretKeyRef: { name: 'coder', key: 'username' } } },
              { name: 'CODER_FIRST_USER_PASSWORD', valueFrom: { secretKeyRef: { name: 'coder', key: 'password' } } },
              { name: 'CODER_SESSION_TOKEN', valueFrom: { secretKeyRef: { name: 'coder-init-token', key: 'token', optional: true } } },
            ],
          }],
        },
      },
    },
  },
}
