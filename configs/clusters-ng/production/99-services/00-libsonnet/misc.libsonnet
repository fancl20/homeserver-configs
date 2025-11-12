{
  local base = self,

  Kustomize():: { [i.key]: i.value for i in std.objectKeysValues(base) } {
    'kustomization.yaml': self.Kustomization,

    Kustomization:: {
      apiVersion: 'kustomize.config.k8s.io/v1beta1',
      kind: 'Kustomization',
      resources: std.objectFields(base),
    },

    Config(file, content):: self {
      local k = super.Kustomization,
      [file + '.raw']: content,
      Kustomization+: {
        configMapGenerator: [{
          name: base.Name,
          namespace: base.Namespace,
          files: [file] + if std.objectHas(k, 'configMapGenerator') then k.configMapGenerator[0].files else [],
        }],
        generatorOptions: {
          annotations: {
            'kustomize.toolkit.fluxcd.io/substitute': 'disabled',
          },
        },
      },
    },
  },

  OnePassword(name=base.Name, spec):: self {
    ['onepassword_' + name + '.yaml']: {
      apiVersion: 'external-secrets.io/v1',
      kind: 'ExternalSecret',
      metadata: {
        name: name,
        namespace: base.Namespace,
      },
      spec: {
        refreshInterval: '1m',
        secretStoreRef: { name: 'onepassword', kind: 'ClusterSecretStore' },
        target: { name: name, creationPolicy: 'Owner' },
      } + spec,
    },
  },
}
