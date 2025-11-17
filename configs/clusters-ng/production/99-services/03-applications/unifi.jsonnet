local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('unifi').Deployment()
.PodContainers([
  {
    name: 'unifi',
    image: images.unifi,
    env: [
      { name: 'TZ', value: 'Australia/Sydney' },
      { name: 'PUID', value: '1000' },
      { name: 'PGID', value: '1000' },
      { name: 'MONGO_HOST', value: '127.0.0.1' },
      { name: 'MONGO_PORT', value: '27017' },
    ],
    envFrom: [
      { secretRef: { name: 'unifi' } },
    ],
    volumeMounts: [
      { name: 'unifi', mountPath: '/config' },
    ],
  },
  {
    name: 'mongo',
    image: images.mongo,
    args: ['--bind_ip', '127.0.0.1'],
    envFrom: [
      { secretRef: { name: 'unifi' } },
    ],
    volumeMounts: [
      { name: 'unifi-db', mountPath: '/data/db' },
      { name: 'config', mountPath: '/docker-entrypoint-initdb.d' },
    ],
  },
  {
    name: 'nginx',
    image: images.nginx,
    volumeMounts: [
      { name: 'config', mountPath: '/etc/nginx/nginx.conf', subPath: 'nginx.conf' },
    ],
  },
])
.PodVolumes([
  { name: 'config', configMap: { name: 'unifi' } },
])
.PodAnnotations({
  'k8s.v1.cni.cncf.io/networks': std.manifestJson([
    {
      name: 'macvlan-static',
      ips: ['192.168.1.10/24'],
    },
  ]),
})
.PersistentVolumeClaim('unifi')
.PersistentVolumeClaim('unifi-db')
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 443, targetPort: 8443 },
  ],
})
.Ingress(port=443, metadata={
  annotations: {
    'nginx.ingress.kubernetes.io/backend-protocol': 'HTTPS',
  },
})
.Kustomize()
.Config('10-init-mongo.sh', |||
  mongosh <<EOF
  use unifi
  db.createUser({
    user: "${MONGO_USER}",
    pwd: "${MONGO_PASS}",
    roles: [
      { db: "${MONGO_DBNAME}", role: "dbOwner" },
      { db: "${MONGO_DBNAME}_stat", role: "dbOwner" },
      { db: "${MONGO_DBNAME}_audit", role: "dbOwner" }
    ]
  })
  EOF
|||)
.Config('nginx.conf', |||
  http {
    server {
      listen 8080;
      location / {
        proxy_pass https://127.0.0.1:8443;
        proxy_ssl_verify off;
      }
    }
  }
|||)
