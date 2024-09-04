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
    LinuxServer(range='*', filters=null):: {
      policy: {
        semver: { range: range + '-ls' },
      },
    } + if filters != null then { filterTags: filters } else {},
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
