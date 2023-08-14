(import 'internal/base.libsonnet') +
(import 'internal/image.libsonnet') +
{
  Volumes:: {
    mass_storage:: {
      name: 'data',
      persistentVolumeClaim: { claimName: 'mass-storage' },
    },
  },

  DefaultPolicy:: {
    LinuxServer:: {
      filterTags: { pattern: '.*-ls.*' },
      policy: {
        semver: { range: 'x-ls' },
      },
    },
  },

  DNSStaticIP:: '192.168.1.3'
}