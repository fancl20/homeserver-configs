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
.Policy(app.DefaultPolicy.LinuxServer(pattern='.*-ls\\d{3,}'))
+
app.Image('dae')
.Repository('registry.local.d20.fan/fancl20/dae')
.Policy(app.DefaultPolicy.Semver('*-testing-') {
  filterTags: {
    extract: '$SEMVER-testing-$PATCH-$TESTING',
    pattern: '^v(?P<SEMVER>[0-9.]+)+(?:\\.p)?(?P<PATCH>\\d+)?-testing-(?P<TESTING>.+)$',
  },
})
+
app.Image('external-dns')
.Repository('registry.k8s.io/external-dns/external-dns')
.Policy(app.DefaultPolicy.Semver())
+
app.Image('fava')
.Repository('registry.local.d20.fan/fancl20/fava')
.Policy(app.DefaultPolicy.Semver('*-testing-'))
+
app.Image('jellyfin')
.Repository('lscr.io/linuxserver/jellyfin')
.Policy(app.DefaultPolicy.LinuxServer('*-1', pattern='.*-ls\\d{3,}'))
+
app.Image('mongo')
.Repository('docker.io/library/mongo')
.Policy(app.DefaultPolicy.Semver('8.*'))
+
app.Image('openssh')
.Repository('lscr.io/linuxserver/openssh-server')
.Policy(app.DefaultPolicy.LinuxServer() {
  filterTags: {
    extract: '$SEMVER.$PATCH-ls$REVISION$LSVER',
    pattern: '^(?P<SEMVER>[0-9.]+)_p(?P<PATCH>\\d+)-r(?P<REVISION>\\d+)-ls(?P<LSVER>\\d+)$',
  },
})
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
app.Image('unifi')
.Repository('lscr.io/linuxserver/unifi-network-application')
.Policy(app.DefaultPolicy.LinuxServer())
+
app.Image('workspace')
.Repository('registry.local.d20.fan/fancl20/workspace')
.Policy({ policy: { alphabetical: { order: 'asc' } } })

