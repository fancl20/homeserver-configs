local app = import 'app.libsonnet';

app.Image('beets')
.Repository('lscr.io/linuxserver/beets')
.Policy(app.DefaultPolicy.LinuxServer())
+
app.Image('bind9')
.Repository('internetsystemsconsortium/bind9')
.Policy({ policy: { numerical: { order: 'asc' } } })
+
app.Image('calibre')
.Repository('lscr.io/linuxserver/calibre-web')
.Policy(app.DefaultPolicy.LinuxServer())
+
app.Image('dae')
.Repository('registry.local.d20.fan/fancl20/dae')
.Policy(app.DefaultPolicy.Semver('*-testing-'))
+
app.Image('external-dns')
.Repository('k8s.gcr.io/external-dns/external-dns')
.Policy(app.DefaultPolicy.Semver())
+
app.Image('fava')
.Repository('registry.local.d20.fan/fancl20/fava')
.Policy(app.DefaultPolicy.Semver('*-testing-'))
+
app.Image('jellyfin')
.Repository('lscr.io/linuxserver/jellyfin')
.Policy(app.DefaultPolicy.LinuxServer('*-1'))
+
app.Image('qbittorrent')
.Repository('lscr.io/linuxserver/qbittorrent')
.Policy(app.DefaultPolicy.LinuxServer('*-r0'))
+
app.Image('registry')
.Repository('docker.io/library/registry')
.Policy(app.DefaultPolicy.Semver())
+
app.Image('roon')
.Repository('registry.local.d20.fan/fancl20/roon')
.Policy({ policy: { alphabetical: { order: 'asc' } } })
+
app.Image('workspace')
.Repository('registry.local.d20.fan/fancl20/workspace')
.Policy({ policy: { alphabetical: { order: 'asc' } } })
