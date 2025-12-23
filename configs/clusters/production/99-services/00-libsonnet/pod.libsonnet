{
  local base = self,

  PodTemplate:: {
    metadata: {
      annotations: {},
      labels: base.Match,
    },
    spec: {
      serviceAccountName: base.Name,
      containers: error 'containers required',
      volumes: [],
    },
  },

  PodAnnotations(annotations):: self {
    PodTemplate+: {
      metadata+: {
        annotations+: annotations,
      },
    },
  },

  PodSecurityContext(securityContext):: self {
    PodTemplate+: {
      spec+: {
        securityContext+: securityContext,
      },
    },
  },

  PodInitContainers(containers):: self {
    PodTemplate+: {
      spec+: {
        initContainers: [{ name: base.Name } + c for c in containers],
      },
    },
  },

  PodContainers(containers):: self {
    PodTemplate+: {
      spec+: {
        containers: [{ name: base.Name } + c for c in containers],
      },
    },
  },

  PodVolumes(volumes):: self {
    PodTemplate+: {
      spec+: {
        volumes+: volumes,
      },
    },
  },

  DNSConfig(config):: self {
    PodTemplate+: {
      spec+: {
        dnsPolicy: 'None',
        dnsConfig+: config,
      },
    },
  },

  RunAsUser(uid=1000, gid=1000):: self {
    PodTemplate+: {
      spec+: {
        securityContext+: {
          runAsUser: uid,
          runAsGroup: gid,
          fsGroup: gid,
          fsGroupChangePolicy: 'OnRootMismatch',
        },
      },
    },
  },

  PersistentVolumeClaim(name=base.Name, spec={}):: self {
    ['pvc_' + name + '.yaml']: {
      apiVersion: 'v1',
      kind: 'PersistentVolumeClaim',
      metadata: {
        name: name,
        namespace: base.Namespace,
      },
      spec: {
        accessModes: ['ReadWriteMany'],
        volumeMode: 'Filesystem',
        resources: {
          requests: { storage: '8Gi' },
        },
      } + spec,
    },

    PodTemplate+: {
      spec+: {
        volumes+: [{
          name: name,
          persistentVolumeClaim: { claimName: name },
        }],
      },
    },
  },
}
