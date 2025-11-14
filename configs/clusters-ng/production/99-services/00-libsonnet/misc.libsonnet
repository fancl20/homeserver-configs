{
  local base = self,

  Kustomize():: { [i.key]: i.value for i in std.objectKeysValues(base) } {
    'kustomization.yaml': {
      apiVersion: 'kustomize.config.k8s.io/v1beta1',
      kind: 'Kustomization',
      resources: std.objectFields(base),

      Files:: [],
    },

    Config(file, content):: self {
      [file + '.raw']: content,
      'kustomization.yaml'+: {
        local files = self.Files,
        configMapGenerator: [{
          name: base.Name,
          namespace: base.Namespace,
          files: files,
        }],
        generatorOptions: {
          annotations: {
            'kustomize.toolkit.fluxcd.io/substitute': 'disabled',
          },
        },
        Files+: [file],
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
