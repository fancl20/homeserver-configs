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
app.Image('clash')
.Repository('registry.local.d20.fan/fancl20/clash')
.Policy({ policy: { alphabetical: { order: 'asc' } } })
+
app.Image('external-dns')
.Repository('k8s.gcr.io/external-dns/external-dns')
.Policy(app.DefaultPolicy.Semver())
+
app.Image('fava')
.Repository('registry.local.d20.fan/fancl20/fava')
.Policy(app.DefaultPolicy.Semver('*-testing-'))
+
app.Image('registry')
.Repository('docker.io/library/registry')
.Policy(app.DefaultPolicy.Semver())
