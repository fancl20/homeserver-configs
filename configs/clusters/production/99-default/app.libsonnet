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
    // Workaround for some irregular tags
    LinuxServer(range='*'):: {
      filterTags: { pattern: '.*-ls\\d{3,}' },
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

  StaticIP:: {
    DNS:: '192.168.1.3',
  },
}
