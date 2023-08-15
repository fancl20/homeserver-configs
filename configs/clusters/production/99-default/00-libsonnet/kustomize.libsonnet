{
  Kustomize(name, namespace, base):: { [i.key]: i.value for i in std.objectKeysValues(base) } {
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
          name: name,
          namespace: namespace,
          files: [file] + if std.objectHas(k, 'configMapGenerator') then k.configMapGenerator[0].files else [],
        }],
      },
    },
  },
}
