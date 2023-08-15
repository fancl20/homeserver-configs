(import '00-libsonnet/base.libsonnet') +
(import '00-libsonnet/image.libsonnet') +
{
  Volumes:: {
    mass_storage:: {
      name: 'data',
      persistentVolumeClaim: { claimName: 'mass-storage' },
    },
  },

  DefaultPolicy:: {
    LinuxServer(range='*'):: {
      filterTags: { pattern: '.*-ls.*' },
      policy: {
        semver: { range: range + '-ls' },
      },
    },
    Semver(range='*'):: {
      policy: {
        semver: { range: range },
      },
    },
  },

  DNSStaticIP:: '192.168.1.3',
}
