local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

(
  app.Base('coder', 'coder', create_namespace=true).Helm('https://helm.coder.com/v2', 'coder', {
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

            echo "Reorganizing templates and pushing to Coder..."
            if [[ -d "/config" ]]; then
              cd "$(mktemp -d)"
              for file in $(ls /config); do
                dst=$(echo "$file" | sed 's/_/\//g')
                mkdir -p "$(dirname "${dst}")"
                cp "/config/${file}" "${dst}"
                echo "Copied ${file} to ${dst}"
              done

              # Push all reorganized templates
              for template_dir in *; do
                if [[ -d "${template_dir}" ]]; then
                  template_name=$(basename "${template_dir}")

                  echo "Pushing template: ${template_name}"
                  if coder templates push -y -d "${template_dir}" "${template_name}"; then
                    echo "Successfully pushed template: ${template_name}"
                  else
                    echo "Failed to push template: ${template_name}"
                  fi
                fi
              done
              echo "Templates reorganized and pushed successfully!"
              cd /
            else
              echo "No templates directory found at /config"
            fi

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
        volumeMounts: [
          { name: 'coder', mountPath: '/config' },
        ],
      }],
      volumes: [{ name: 'coder', configMap: { name: 'coder' } }],
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
  .Nested('coder-db').StatefulSet()
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
  .Kustomize()
  .ConfigNameReference([
    { path: 'spec/values/coder/volumes/configMap/name', kind: 'HelmRelease' },
  ])
  + import 'coder.d/kubernetes-devcontainer/template.libsonnet'
).AddTemplates()
