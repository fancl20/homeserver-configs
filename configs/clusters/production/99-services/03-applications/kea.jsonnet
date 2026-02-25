local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('kea').Deployment()
.PodContainers([{
  image: images.kea,
  env: [
    { name: 'TZ', value: 'Australia/Sydney' },
  ],
  volumeMounts: [
    { name: 'config', mountPath: '/etc/kea/kea-dhcp4.conf', subPath: 'kea-dhcp4.conf' },
    { name: 'kea', mountPath: '/var/lib/kea', subPath: 'var/lib/kea' },
  ],
}])
.PodAnnotations({
  'k8s.v1.cni.cncf.io/networks': std.manifestJson([
    {
      name: 'macvlan-static',
      ips: ['192.168.1.19/24'],
    },
  ]),
})
.PodVolumes([
  { name: 'config', configMap: { name: 'kea' } },
])
.PersistentVolumeClaim()
.Kustomize()
.Config('kea-dhcp4.conf', std.manifestJson({
  Dhcp4: {
    'interfaces-config': {
      interfaces: ['net1'],
    },
    'lease-database': {
      type: 'memfile',
      persist: true,
      name: '/var/lib/kea/dhcp4.leases',
    },
    'hooks-libraries': [
      { library: '/usr/lib/kea/hooks/libdhcp_lease_cmds.so' },
      {
        library: '/usr/lib/kea/hooks/libdhcp_ha.so',
        parameters: {
          'high-availability': [{
            'this-server-name': 'kea',
            mode: 'hot-standby',
            peers: [
              {
                name: 'vyos',
                url: 'http://192.168.1.1:647/',
                role: 'standby',
              },
              {
                name: 'kea',
                url: 'http://192.168.1.19:647/',
                role: 'primary',
              },
            ],
          }],
        },
      },
    ],
    subnet4: [
      {
        id: 1,
        subnet: '192.168.1.0/24',
        pools: [
          { pool: '192.168.1.32 - 192.168.1.159' },
        ],
        'option-data': [
          { name: 'routers', data: '192.168.1.1' },
          { name: 'domain-name-servers', data: '192.168.1.1' },
        ],
        reservations: [{
          // PlayStation5
          'hw-address': '00:e4:21:e8:79:0c',
          'option-data': [
            { name: 'routers', data: '192.168.1.20' },
            { name: 'domain-name-servers', data: '192.168.1.20' },
          ],
        }, {
          // MSI B650I Edge Ethernet
          'hw-address': '04:7c:16:4f:8b:e1',
          'option-data': [
            { name: 'routers', data: '192.168.1.20' },
            { name: 'domain-name-servers', data: '192.168.1.20' },
          ],
        }, {
          // MSI B650I Edge Wi-Fi
          'hw-address': 'f0:a6:54:4e:f9:0d',
          'option-data': [
            { name: 'routers', data: '192.168.1.20' },
            { name: 'domain-name-servers', data: '192.168.1.20' },
          ],
        }],
      },
    ],
  },
}))
