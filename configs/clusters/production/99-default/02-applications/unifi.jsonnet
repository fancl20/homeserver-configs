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
      { name: 'config', mountPath: '/docker-entrypoint-initdb.d/10-init.sh', subPath: '10-init.sh' },
      { name: 'config', mountPath: '/docker-entrypoint-initdb.d/20-init-mongo.js', subPath: '20-init-mongo.js' },
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
  init_mongo_js: {
    path: 'homeserver/data/unifi',
    template: |||
      db.getSiblingDB("unifi").createUser({
        user: "unifi",
        pwd: "{{ .Data.data.db_password }}",
        roles: [
          { db: "unifi", role: "dbOwner" },
          { db: "unifi_stat", role: "dbOwner" }
        ]
      });
    |||,
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
.Config('20-init-mongo.js', 'placeholder')
.Config('10-init.sh', 'cp /vault/secrets/init_mongo_js /docker-entrypoint-initdb.d/')
