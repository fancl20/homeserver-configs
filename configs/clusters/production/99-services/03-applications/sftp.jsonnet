local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('sftp').Deployment()
.PodContainers([{
  image: images.openssh,
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
    { name: 'PUID', value: '1000' },
    { name: 'PGID', value: '1000' },
    { name: 'PASSWORD_ACCESS', value: 'true' },
    { name: 'USER_NAME', value: 'fancl20' },
  ],
  envFrom: [
    { secretRef: { name: 'sftp' } },
  ],
  volumeMounts: [
    { name: 'sftp', mountPath: '/config'},
    { name: 'data', mountPath: '/shared'},
  ],
}])
.PodVolumes([
  app.Volumes.shared_data,
])
.PersistentVolumeClaim()
.OnePassword(spec={
  dataFrom: [{
    extract: { key: 'Shared SFTP', property: 'public key' },
    rewrite: [
      { regexp: { source: 'public key', target: 'PUBLIC_KEY' } },
    ],
  }, {
    extract: { key: 'Shared SFTP', property: 'password' },
    rewrite: [
      { regexp: { source: 'password', target: 'USER_PASSWORD' } },
    ],
  }],
})
.Service({
  ports: [
    { name: 'ssh', protocol: 'TCP', port: 22, targetPort: 2222 },
  ],
}, external_dns=true)
