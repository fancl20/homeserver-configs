{
  Image(name, namespace='flux-system'):: {
    Repository(repository, spec={}):: self {
      [name]:: repository,
      [name + '_repository.yaml']: {
        apiVersion: 'image.toolkit.fluxcd.io/v1beta2',
        kind: 'ImageRepository',
        metadata: {
          name: name,
          namespace: namespace,
        },
        spec: spec {
          image: repository,
          interval: '1h',
        },
      },
    },
    Policy(spec):: self {
      [name + '_policy.yaml']: {
        apiVersion: 'image.toolkit.fluxcd.io/v1beta2',
        kind: 'ImagePolicy',
        metadata: {
          name: name,
          namespace: namespace,
        },
        spec: spec {
          imageRepositoryRef: { name: name },
        },
      },
    },
  },
}
