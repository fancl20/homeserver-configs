(import '../templates.libsonnet') {
  Templates+: [{
    name: std.reverse(std.split(std.thisFile, '/'))[1],
    'main.tf': importstr 'main.tf',
    'README.md': importstr 'README.md',
  }],
}
