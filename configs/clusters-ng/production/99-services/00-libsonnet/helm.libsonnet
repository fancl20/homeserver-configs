local addons = import 'addons.libsonnet';

{
  Helm(name, namespace, url):: {
    'helmrepository.yaml': {
      apiVersion: 'source.toolkit.fluxcd.io/v1',
      kind: 'HelmRepository',
      metadata: {
        name: name,
        namespace: namespace,
      },
      spec: {
        interval: '1h0s',
        url: url
      },
    },

    Release(release_name=name, chart=name, values={}):: self {
      ['helmrelease_' + release_name + '.yaml']: {
        apiVersion: 'helm.toolkit.fluxcd.io/v2',
        kind: 'HelmRelease',
        metadata: {
          name: release_name,
          namespace: namespace,
        },
        spec: {
          interval: '15m',
          chart: {
            spec: {
              chart: chart,
              sourceRef: { kind: 'HelmRepository', name: name },
            },
          },
          values: values,
        },
      },
    },

    OnePassword(secret_name=name, spec):: self + addons.OnePassword(secret_name, namespace, spec),
    Kustomize():: addons.Kustomize(name, namespace, self),
  },
}
