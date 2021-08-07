module "roon_server" {
  source = "../modules/general-service"
  name   = "roon-server"
  deployment = {
    image = {
      repository = "ghcr.io/fancl20/roon-server"
    }
    env = [
      { name = "TZ", value = "Australia/Sydney" },
    ]
    volumeMounts = [
      { name = "data", mountPath = "/data", subPath = "roon-server/data" },
      { name = "data", mountPath = "/backup", subPath = "roon-server/backup" },
      { name = "data", mountPath = "/music", subPath = "shared/music" },
    ]
    volumes = [
      local.mass_storage_volume,
    ]
  }
  services = {
    roon-server = {
      portsRanges = [
        { prefix = "roon-tcp", protocol = "TCP", start = 9100, end = 9210 },
        { prefix = "roon-udp", protocol = "UDP", start = 9000, end = 9010 },
      ]
      type = "LoadBalancer"
    }
  }
}
