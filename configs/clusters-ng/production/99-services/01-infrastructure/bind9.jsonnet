local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('bind9').Deployment()
.PodContainers([{
  image: images.bind9,
  resources: {
    requests: { memory: '128Mi', cpu: '100m' },
    limits: { memory: '128Mi', cpu: '200m' },
  },
  volumeMounts: [
    { name: 'config', mountPath: '/etc/bind/named.conf', subPath: 'named.conf' },
    { name: 'config', mountPath: '/var/lib/bind/local.d20.fan.zone', subPath: 'local.d20.fan.zone' },
    { name: 'secret', mountPath: '/etc/bind/bind9_externaldns_key', subPath: 'bind9_externaldns_key' },
  ],
}])
.PodVolumes([
  { name: 'config', configMap: { name: 'bind9' } },
  { name: 'secret', secret: { secretName: 'bind9' } },
])
.Service({
  ports: [
    { name: 'dns-udp', protocol: 'UDP', port: 53, targetPort: 5353 },
    { name: 'dns-tcp', protocol: 'TCP', port: 53, targetPort: 5353 },
  ],
  type: 'LoadBalancer',
}, load_balancer_ip=app.StaticIP.DNS)
.Kustomize()
.Config('named.conf', |||
  options {
    directory "/var/cache/bind";
    auth-nxdomain no; # conform to RFC1035
    interface-interval 0; # From 9.9.5 ARM, disables interfaces scanning to prevent unwanted stop listening
    listen-on-v6 { none; }; # Listen on local interfaces only(IPV4)
    listen-on port 5353 { 0.0.0.0/0; };
    allow-transfer { none; }; # Do not transfer the zone information to the secondary DNS
    allow-query { any; };
    allow-recursion { any; };
    max-cache-size 64m;
    max-cache-ttl 60;
    max-ncache-ttl 60;
    version none; # Do not make public version of BIND
  };
  controls {};

  include "/etc/bind/bind9_externaldns_key";
  zone "local.d20.fan" {
    type master;
    file "/var/lib/bind/local.d20.fan.zone";
    allow-transfer { key "bind9-externaldns"; };
    update-policy { grant bind9-externaldns zonesub ANY; };
  };
|||)
.Config('local.d20.fan.zone', |||
  $TTL 60 ; 1 minute
  @                               IN SOA  local.d20.fan. root.local.d20.fan. (
                                  16         ; serial
                                  60         ; refresh (1 minute)
                                  60         ; retry (1 minute)
                                  60         ; expire (1 minute)
                                  60         ; minimum (1 minute)
                                  )
                          NS      ns.local.d20.fan.
  ns                      A       %(DNS)s
||| % app.StaticIP)
