local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('chrome-devtools-mcp').Deployment()
.PodContainers([{
  image: images.chrome,
  command: ['npx', '-y', 'supergateway', '--stdio', |||
    npx -y chrome-devtools-mcp@latest \
      --executablePath=/opt/chrome/chrome \
      --slim \
      --headless \
      --isolated
  |||, '--outputTransport', 'streamableHttp', '--stateful', '--cors'],
}])
.Service({
  ports: [{ name: 'http', protocol: 'TCP', port: 80, targetPort: 8000 }],
})
.HTTPRoute()
