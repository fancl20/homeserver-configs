local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('youtrack').Deployment()
.PodInitContainers([{
  name: 'init',
  image: images.youtrack,
  command: ['/bin/bash', '-ex', '-c', |||
    CONFIG=/opt/youtrack/conf/youtrack.jvmoptions
    if [[ ! -e "${CONFIG}" ]] && [[ -e "${CONFIG}.dist" ]]; then
      echo '-Ddisable.configuration.wizard.on.upgrade=true' | cat "${CONFIG}.dist" - > "${CONFIG}"
    fi
  |||],
  volumeMounts: [
    { name: 'youtrack', mountPath: '/opt/youtrack/conf', subPath: 'conf' },
  ],
}])
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
