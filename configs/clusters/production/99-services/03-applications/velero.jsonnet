local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('velero', 'velero', create_namespace=true).Helm('https://vmware-tanzu.github.io/helm-charts', 'velero', {
  kubectl: {
    image: {
      repository: 'public.ecr.aws/bitnami/kubectl',  // https://github.com/vmware-tanzu/helm-charts/issues/698
    },
  },
  configuration: {
    backupStorageLocation: [{
      name: 'wasabi',
      provider: 'aws',
      bucket: 'fancl20-backups',
      default: true,
      config: {
        region: 'ap-southeast-2',
        s3Url: 'https://s3.ap-southeast-2.wasabisys.com',
      },
      credential: {
        name: 'velero',
        key: 'credentials',
      },
    }],
    volumeSnapshotLocation: [{
      name: 'rook-cephfs',
      provider: 'csi',
    }],
    defaultSnapshotMoveData: true,
    features: 'EnableCSI',
  },
  initContainers: [{
    name: 'velero-plugin-for-aws',
    image: images['velero-plugin-aws'],
    imagePullPolicy: 'IfNotPresent',
    volumeMounts: [
      { name: 'plugins', mountPath: '/target' },
    ],
  }],
  deployNodeAgent: true,
  schedules: {
    daily: {
      schedule: 'CRON_TZ=Australia/Sydney 0 4 * * *',
      template: {
        includedNamespaces: ['default'],
        snapshotVolumes: true,
        storageLocation: 'wasabi',
        volumeSnapshotLocations: ['rook-cephfs'],
        ttl: '720h0m0s',
      },
    },
  },
})
.OnePassword(spec={
  dataFrom: [
    { extract: { key: 'Wasabi S3' } },
  ],
})
