module "roon_server" {
  source = "../modules/general-service"
  name   = "roon-server"
  deployment = {
    containers = [{
      image = "ghcr.io/fancl20/roon-server:latest"
      env = [
        { name = "TZ", value = "Australia/Sydney" },
      ]
      volumeMounts = [
        { name = "data", mountPath = "/data", subPath = "roon-server/data" },
        { name = "data", mountPath = "/backup", subPath = "roon-server/backup" },
        { name = "data", mountPath = "/music", subPath = "shared/music" },
      ]
    }]
    volumes = [
      local.mass_storage_volume,
    ]
    podAnnotations = {
      "k8s.v1.cni.cncf.io/networks" = jsonencode([
        {
          name    = "macvlan"
          ips     = ["192.168.1.244/24"]
          mac     = "26:1e:94:c2:23:39"
          gateway = ["192.168.1.1"]
        }
      ])
    }
  }
}
