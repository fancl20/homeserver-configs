local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('youtrack').Deployment()
.PodContainers([{
  image: images.youtrack,
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
  ],
  volumeMounts: [
    { name: 'youtrack', mountPath: '/opt/youtrack/data', subPath: 'data' },
    { name: 'youtrack', mountPath: '/opt/youtrack/conf', subPath: 'conf' },
    { name: 'youtrack', mountPath: '/opt/youtrack/backups', subPath: 'backups' },
  ],
}])
.RunAsUser(13001, 13001)
.PersistentVolumeClaim()
.Service({
  ports: [
    { name: 'webui', protocol: 'TCP', port: 80, targetPort: 8080 },
  ],
})
.HTTPRoute()