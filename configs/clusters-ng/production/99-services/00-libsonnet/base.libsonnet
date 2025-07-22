local kustomize = import 'kustomize.libsonnet';

{
  Base(name, namespace='default'):: {
    local match = { 'app.kubernetes.io/name': name },
    local hostname = name + '.local.d20.fan',

    'deployment.yaml': self.Deployment,
    'serviceaccount.yaml': self.ServiceAccount,

    Deployment:: {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: name,
        namespace: namespace,
      },
      spec: {
        replicas: 1,
        strategy: {
          rollingUpdate: {
            maxSurge: 0,
            maxUnavailable: '100%',
          },
        },
        selector: {
          matchLabels: match,
        },
        template: {
          metadata: {
            annotations: {},
            labels: match,
          },
          spec: {
            serviceAccountName: name,
            containers: error 'containers required',
            volumes: [],
          },
        },
      },
    },

    PodAnnotations(annotations):: self {
      Deployment+: {
        spec+: {
          template+: {
            metadata+: {
              annotations+: annotations,
            },
          },
        },
      },
    },

    PodSecurityContext(securityContext):: self {
      Deployment+: {
        spec+: {
          template+: {
            spec+: {
              securityContext+: securityContext,
            },
          },
        },
      },
    },

    PodContainers(containers):: self {
      Deployment+: {
        spec+: {
          template+: {
            spec+: {
              containers: [{ name: name } + c for c in containers],
            },
          },
        },
      },
    },

    PodVolumes(volumes):: self {
      Deployment+: {
        spec+: {
          template+: {
            spec+: {
              volumes+: volumes,
            },
          },
        },
      },
    },

    ServiceAccount:: {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: {
        name: name,
        namespace: namespace,
      },
    },

    ClusterRole(rules):: self {
      'clusterrole.yaml': {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'ClusterRole',
        metadata: {
          name: name,
        },
        rules: rules,
      },
    },

    ClusterRoleBinding(role_ref={
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: name,
    }):: self {
      'clusterrolebinding.yaml': {
        apiVersion: 'rbac.authorization.k8s.io/v1',
        kind: 'ClusterRoleBinding',
        metadata: {
          name: name,
        },
        roleRef: role_ref,
        subjects: [{
          kind: 'ServiceAccount',
          name: name,
          namespace: namespace,
        }],
      },
    },

    Service(spec, service_name=name, external_dns=false,):: self {
      local merged = { type: if external_dns then 'LoadBalancer' else 'ClusterIP', selector: match } + spec,
      ['service_' + service_name + '.yaml']: {
        apiVersion: 'v1',
        kind: 'Service',
        metadata: {
          name: service_name,
          namespace: namespace,
          annotations: if external_dns then {
            'external-dns.alpha.kubernetes.io/hostname': hostname,
          },
        },
        spec: merged + if merged.type == 'LoadBalancer' then { allocateLoadBalancerNodePorts: false } else {},
      },
    },

    Ingress(service=name, port=80, metadata={}):: self {
      'ingress.yaml': {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'Ingress',
        metadata: {
          name: name,
          namespace: namespace,
        } + metadata,
        spec: {
          tls: [{ hosts: [hostname] }],
          rules: [{
            host: hostname,
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

    PersistentVolumeClaim(pvc_name=name, spec={}):: self {
      ['pvc_' + pvc_name + '.yaml']: {
        apiVersion: 'v1',
        kind: 'PersistentVolumeClaim',
        metadata: {
          name: pvc_name,
          namespace: namespace,
        },
        spec: {
          accessModes: [ "ReadWriteMany" ],
          volumeMode: "Filesystem",
          resources: {
            requests: { storage: "8Gi" },
          },
        } + spec,
      },
      Deployment+: {
        spec+: {
          template+: {
            spec+: {
              volumes+: [{
                name: pvc_name,
                persistentVolumeClaim: { claimName: pvc_name },
              }],
            },
          },
        },
      },
    },

    Kustomize():: kustomize.Kustomize(name, namespace, self),
  },
}
