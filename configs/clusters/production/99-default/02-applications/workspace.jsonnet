local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('workspace-common')
.PodContainers([{
  image: images.workspace,
  command: ['/bin/bash', '-ex', '-c', |||
    cp /vault/secrets/authorized_keys /root/.ssh/
    cp /vault/secrets/id_rsa /root/.ssh/
    chmod 700 /root/.ssh && chmod 600 /root/.ssh/*

    exec /usr/sbin/sshd -D -f /etc/config/sshd_config
  |||],
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
  ],
  volumeMounts: [
    { name: 'config', mountPath: '/etc/config' },
    { name: 'data', mountPath: '/root', subPath: 'workspaces/common' },
    { name: 'ssh', mountPath: '/root/.ssh' },
  ],
}])
.PodVolumes([
  app.Volumes.mass_storage,
  { name: 'config', configMap: { name: 'sshd_config' } },
  { name: 'ssh', emptyDir: {} },
])
.VaultInjector('workspace_ssh', {
  authorized_keys: {
    path: 'homeserver/data/ssh',
    template: |||
      {{ with secret "homeserver/data/ssh" -}}
      {{ .Data.data.public_key }}
      {{- end }}
    |||,
  },
  id_rsa: {
    path: 'homeserver/data/ssh',
    template: |||
      {{ with secret "homeserver/data/ssh" -}}
      {{ .Data.data.private_key }}
      {{- end }}
    |||,
  },
})
.Service({
  ports: [
    { name: 'ssh', protocol: 'TCP', port: 22, targetPort: 2222 },
  ],
}, external_dns=true)
.Kustomize()
.Config('sshd_config', |||
  Port 2222
  PermitRootLogin yes
  ChallengeResponseAuthentication no
  PrintMotd no
  AcceptEnv LANG LC_*
  Subsystem       sftp    /usr/lib/openssh/sftp-server
|||)
