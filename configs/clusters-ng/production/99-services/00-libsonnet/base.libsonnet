local misc = import 'misc.libsonnet';
local pod = import 'pod.libsonnet';
local service = import 'service.libsonnet';
local serviceaccount = import 'serviceaccount.libsonnet';

{
  Base(name, namespace='default', create_namespace=false):: {
    local root = {
      Name:: name,
      Namespace:: namespace,
      Match:: { 'app.kubernetes.io/name': name },
      Hostname:: name + '.local.d20.fan',
      [if create_namespace then 'namespace.yaml']: {
        apiVersion: 'v1',
        kind: 'Namespace',
        metadata: {
          name: namespace,
        },
      },
      Done():: { [i.key]: i.value for i in std.objectKeysValues(self) },
    },

    local spec(base) = {
      apiVersion: 'apps/v1',
      metadata: {
        name: base.Name,
        namespace: base.Namespace,
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
          matchLabels: base.Match,
        },
        template: base.PodTemplate,
      },
    },


    Deployment():: (root + pod + serviceaccount + service + misc) {
      'deployment.yaml': spec(self) {
        kind: 'Deployment',
      },
    }.ServiceAccount(),

    StatefulSet(service_name=name):: (root + pod + serviceaccount + service + misc) {
      'statefulset.yaml': spec(self) {
        kind: 'StatefulSet',
        spec+: {
          serviceName: service_name,
        },
      },
    }.ServiceAccount(),

    Helm(repo, chart, values):: (root + serviceaccount + service + misc) {
      local base = self,

      'helmrepository.yaml': {
        apiVersion: 'source.toolkit.fluxcd.io/v1',
        kind: 'HelmRepository',
        metadata: {
          name: base.Name,
          namespace: base.Namespace,
        },
        spec: {
          interval: '1h0s',
          url: repo,
        },
      },
      'helmrelease.yaml': {
        apiVersion: 'helm.toolkit.fluxcd.io/v2',
        kind: 'HelmRelease',
        metadata: {
          name: base.Name,
          namespace: base.Namespace,
          annotations: {
            'kustomize.toolkit.fluxcd.io/substitute': 'disabled',
          },
        },
        spec: {
          interval: '15m',
          chart: {
            spec: {
              chart: chart,
              sourceRef: { kind: 'HelmRepository', name: base.Name },
            },
          },
          values: values,
        },
      },
    },
  },
}
