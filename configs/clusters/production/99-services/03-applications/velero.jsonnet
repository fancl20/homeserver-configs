local app = import '../app.libsonnet';

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
  },
  initContainers: [{
    name: 'velero-plugin-for-aws',
    image: 'velero/velero-plugin-for-aws:v1.10.0',
    imagePullPolicy: 'IfNotPresent',
    volumeMounts: [
      { name: 'plugins', mountPath: '/plugins' },
    ],
  }, {
    name: 'velero-plugin-for-csi',
    image: 'velero/velero-plugin-for-csi:v0.8.0',
    imagePullPolicy: 'IfNotPresent',
    volumeMounts: [
      { name: 'plugins', mountPath: '/plugins' },
    ],
  }],
  schedules: {
    daily: {
      schedule: 'CRON_TZ=Australia/Sydney 0 4 * * *',
      template: {
        includedNamespaces: ['default', 'coder'],
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
