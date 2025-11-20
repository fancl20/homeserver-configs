{
  local base = self,

  Service(spec, name=base.Name, external_dns=false, load_balancer_ip=''):: self {
    local merged = { type: if external_dns then 'LoadBalancer' else 'ClusterIP', selector: base.Match } + spec,
    ['service_' + name + '.yaml']: {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: name,
        namespace: base.Namespace,
        annotations: {
          [if external_dns then 'external-dns.alpha.kubernetes.io/hostname']: base.Hostname,
          [if load_balancer_ip != '' then 'metallb.io/loadBalancerIPs']: load_balancer_ip,
        },
      },
      spec: merged {
        [if merged.type == 'LoadBalancer' then 'allocateLoadBalancerNodePorts']: false,
      },
    },
  },

  HTTPRoute(service=base.Name, port=80, wildcard=false, metadata={}):: self {
    'httproute.yaml': {
      apiVersion: 'gateway.networking.k8s.io/v1',
      kind: 'HTTPRoute',
      metadata: {
        name: base.Name,
        namespace: base.Namespace,
      } + metadata,
      spec: {
        hostnames: [base.Hostname] + if wildcard then ['*.' + base.Hostname] else [],
        parentRefs: [{
          group: 'gateway.networking.k8s.io',
          kind: 'Gateway',
          name: 'default',
          namespace: 'nginx-gateway',
          sectionName: 'https',
        }],
        rules: [{
          backendRefs: [{
            group: '',
            kind: 'Service',
            name: service,
            port: port,
          }],
        }],
      },
    },
  },
}
