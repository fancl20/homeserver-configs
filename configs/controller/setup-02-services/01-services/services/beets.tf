module "beets" {
  source = "../modules/general-service"
  name   = "beets"
  deployment = {
    containers = [{
      image = "lscr.io/linuxserver/beets"
      env = [
        { name = "TZ", value = "Australia/Sydney" },
        { name = "DOCKER_MODS", value = "ghcr.io/fancl20/beets-shntool:latest" },
      ]
      volumeMounts = [
        { name = "data", mountPath = "/config", subPath = "beets/config" },
        { name = "data", mountPath = "/music", subPath = "shared/music" },
        { name = "data", mountPath = "/downloads", subPath = "shared/downloads" },
      ]
    }]
    volumes = [
      local.mass_storage_volume,
    ]
  }
  services = [{
    ports = [
      { name = "webui", protocol = "TCP", port = 80, targetPort = 8337 },
    ]
  }]
  ingress = {
    enabled = true
  }
  domain_suffix = var.domain_suffix
}
