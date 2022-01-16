module "qbittorrent" {
  source = "../modules/general-service"
  name   = "qbittorrent"
  deployment = {
    image = {
      repository = "lscr.io/linuxserver/qbittorrent"
    }
    env = [
      { name = "TZ", value = "Australia/Sydney" },
      { name = "PUID", value = "0" },
      { name = "GUID", value = "0" },
    ]
    volumeMounts = [
      { name = "data", mountPath = "/config", subPath = "qbittorrent/config" },
      { name = "data", mountPath = "/downloads", subPath = "shared/downloads" },
    ]
    volumes = [
      local.mass_storage_volume,
    ]
  }
  services = {
    qbittorrent = {
      ports = [
        { name = "bittorrent-tcp", protocol = "TCP", port = 6881, targetPort = 6881 },
        { name = "bittorrent-udp", protocol = "UDP", port = 6881, targetPort = 6881 },
      ]
      type = "LoadBalancer"
    }
    qbittorrent-ui = {
      ports = [
        { name = "webui", protocol = "TCP", port = 80, targetPort = 8080 },
      ]
    }
  }
  ingress = {
    enabled = true
    backend = { service = "qbittorrent-ui" }
  }
  domain_suffix = var.domain_suffix
}
