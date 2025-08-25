(import '00-libsonnet/base.libsonnet') +
(import '00-libsonnet/image.libsonnet') +
{
  Volumes:: {
    shared_data:: {
      name: 'data',
      persistentVolumeClaim: { claimName: 'shared-data' },
    },
  },

  DefaultPolicy:: {
    LinuxServer(range='*', pattern='.*-ls'):: {
      filterTags: { pattern: pattern },
      policy: {
        semver: { range: range + '-ls' },
      },
    },
    Semver(range='*', pattern='.*'):: {
      filterTags: { pattern: pattern },
      policy: {
        semver: { range: range },
      },
    },
  },

  StaticIP:: {
    DNS:: '192.168.1.3',
  },
}

