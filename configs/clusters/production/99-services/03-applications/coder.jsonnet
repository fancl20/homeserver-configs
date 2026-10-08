local app = import '../app.libsonnet';

// Pinned by hand: the image transforms in components/images only reach rendered
// workload manifests, not values nested inside the HelmRelease. Bump alongside
// the postgres entry in components/images/kustomization.yaml.
local postgresImage = 'docker.io/library/postgres:18.6';

app.Base('coder', 'coder', create_namespace={
  labels: {
    'pod-security.kubernetes.io/enforce': 'privileged',
    'pod-security.kubernetes.io/audit': 'privileged',
    'pod-security.kubernetes.io/warn': 'privileged',
  },
}).Helm('https://helm.coder.com/v2', 'coder', {
  local domain = 'coder.local.d20.fan',
  coder: {
    env: [
      { name: 'CODER_PG_CONNECTION_URL', valueFrom: { secretKeyRef: { name: 'coder-db', key: 'url' } } },
      { name: 'CODER_ACCESS_URL', value: 'https://' + domain },
      { name: 'CODER_WILDCARD_ACCESS_URL', value: '*.' + domain },
    ],
    resources: {
      requests: { memory: '1024Mi' },
    },
    volumes: [
      { name: 'coder-db', persistentVolumeClaim: { claimName: 'coder-db' } },
    ],
    initContainers: [{
      name: 'coder-init',
      image: 'ghcr.io/coder/coder:latest',
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
      // Native sidecar: postgres starts before the coder container and shares
      // the coder-db PVC with the old coder-db StatefulSet layout.
      name: 'postgres',
      image: postgresImage,
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
    }, {
      // POSTGRES_PASSWORD only takes effect at initdb time, so the database
      // keeps whatever password it was created with whenever the secret drifts
      // (e.g. terraform state loss regenerating random_password.coder_db).
      // This converges the database to the secret on every start; loopback
      // connections are trust-auth in the official image, so it works even
      // while the passwords disagree.
      name: 'coder-db-sync',
      image: postgresImage,
      command: [
        '/bin/sh',
        '-ec',
        |||
          : "${POSTGRES_PASSWORD:?missing}"
          until pg_isready -h 127.0.0.1 -q; do sleep 1; done
          psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_USER" \
            -v ON_ERROR_STOP=1 \
            -v pw="$POSTGRES_PASSWORD" \
            -c "ALTER USER \"$POSTGRES_USER\" WITH PASSWORD :'pw'"
        |||,
      ],
      envFrom: [
        { secretRef: { name: 'coder-db' } },
      ],
    }],
  },
})
.HTTPRoute(wildcard=true)
.Role(name='coder-init', rules=[{
  apiGroups: [''],
  resources: ['secrets'],
  verbs: ['create', 'update'],
}])
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
.PersistentVolumeClaim('coder-db')
