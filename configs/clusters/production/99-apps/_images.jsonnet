local app = import '_app.libsonnet';

app.Image('beets')
.Repository('lscr.io/linuxserver/beets')
.Policy(app.DefaultPolicy.LinuxServer)
+
app.Image('bind9')
.Repository('internetsystemsconsortium/bind9')
.Policy(app.DefaultPolicy.LinuxServer)
