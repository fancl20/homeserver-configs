local app = import '_app.libsonnet';
local images = import '_images.jsonnet';

app.Base('bind9')
.PodContainers([{
  image: images.bind9,
  command: ['/bin/sh', '-e', '-c', |||
    rm -f /etc/bind/pri/*.jnl
    exec /usr/sbin/named -g -c /etc/bind/named.conf -u bind
  |||],
  resources: {
    requests: { memory: '128Mi', cpu: '100m' },
    limits: { memory: '128Mi', cpu: '200m' },
  },
  volumeMounts: [
    { name: 'config', mountPath: '/etc/bind/named.conf', subPath: 'named.conf' },
    { name: 'config', mountPath: '/etc/bind/local.d20.fan.zone', subPath: 'local.d20.fan.zone' },
  ],
}])
.PodVolumes([
  { name: 'config', configMap: { name: 'bind9' } },
])
.VaultInjector('external_dns', {
  bind9_externaldns_key: {
    path: 'homeserver/data/bind9',
    template: |||
      {{ with secret "homeserver/data/bind9" -}}
      key externaldns-key {
        algorithm {{ .Data.data.externaldns_key_algorithm }};
        secret "{{ .Data.data.externaldns_key_secret }}";
      };
      {{- end }}
    |||,
  },
})
.Service({
  ports: [
    { name: 'dns-udp', protocol: 'UDP', port: 53, targetPort: 5353 },
    { name: 'dns-tcp', protocol: 'TCP', port: 53, targetPort: 5353 },
  ],
  type: 'LoadBalancer',
  loadBalancerIP: app.DNSStaticIP,
})
.Kustomize()
.Config('named.conf', |||
  options {
    directory "/var/cache/bind";
    query-source address * port *; # Exchange port between DNS servers
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
  controls { };

  include "/vault/secrets/bind9_externaldns_key";
  zone "local.d20.fan" {
    type master;
    file "/etc/bind/local.d20.fan.zone";
    allow-transfer { key "externaldns-key"; };
    update-policy { grant externaldns-key zonesub ANY; };
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
  ns                      A       %(DNSStaticIP)s
||| % app)
