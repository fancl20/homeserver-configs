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

  Ingress(service=base.Name, port=80, metadata={}):: self {
    'ingress.yaml': {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: {
        name: base.Name,
        namespace: base.Namespace,
      } + metadata,
      spec: {
        tls: [{ hosts: [base.Hostname] }],
        rules: [{
          host: base.Hostname,
          http: {
            paths: [{
              path: '/',
              pathType: 'Prefix',
              backend: {
                service: {
                  name: service,
                  port: { number: port },
                },
              },
            }],
          },
        }],
      },
    },
  },
}
