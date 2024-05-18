local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('unifi')
.PodContainers([
  {
    name: 'unifi',
    image: images.unifi,
    env: [
      { name: 'TZ', value: 'Australia/Sydney' },
      { name: 'MONGO_HOST', value: '127.0.0.1' },
      { name: 'FILE__MONGO_PASS', value: '/vault/secrets/unifi_mongo_pass' },
    ],
    volumeMounts: [
      { name: 'data', mountPath: '/config', subPath: 'unifi/data/config' },
    ],
  },
  {
    name: 'mongo',
    image: images.mongo,
    volumeMounts: [
      { name: 'data', mountPath: '/data/db', subPath: 'unifi/data/db' },
      { name: 'config', mountPath: '/docker-entrypoint-initdb.d' },
    ],
  },
])
.PodVolumes([
  app.Volumes.mass_storage,
  { name: 'config', configMap: { name: 'unifi' } },
])
.VaultInjector('unifi', {
  unifi_mongo_pass: {
    path: 'homeserver/data/unifi',
    template: '{{ with secret "homeserver/data/unifi" -}}{{ .Data.data.db_password }}{{- end }}',
  },
})
.PodAnnotations({
  'k8s.v1.cni.cncf.io/networks': std.manifestJson([
    {
      name: 'macvlan',
      ips: ['192.168.1.246/24'],
      mac: '26:1e:94:c2:23:41',
      gateway: ['192.168.1.1'],
    },
  ]),
})
.Kustomize()
.Config('10-init-mongo.sh', |||
  set -e

  mongo <<EOF
  use unifi
  db.createUser({
    user: 'unifi',
    pwd: '$(cat /vault/secrets/unifi_mongo_pass)',
    roles: [
      { db: 'unifi', role: 'dbOwner' },
      { db: 'unifi_stat', role: 'dbOwner' },
    ]
  })
  EOF
|||)
