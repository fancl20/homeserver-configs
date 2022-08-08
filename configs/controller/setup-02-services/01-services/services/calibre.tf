module "calibre" {
  source = "../modules/general-service"
  name   = "calibre"
  deployment = {
    containers = [{
      image = "lscr.io/linuxserver/calibre-web"
      env = [
        { name = "TZ", value = "Australia/Sydney" },
        { name = "PUID", value = "0" },
        { name = "GUID", value = "0" },
        { name = "DOCKER_MODS", value = "linuxserver/mods:universal-calibre" },
      ]
      volumeMounts = [
        { name = "data", mountPath = "/config", subPath = "calibre/config" },
        { name = "data", mountPath = "/books", subPath = "shared/calibre" },
      ]
    }]
    volumes = [
      local.mass_storage_volume,
    ]
  }
  services = [{
    ports = [
      { name = "webui", protocol = "TCP", port = 80, targetPort = 8083 },
    ]
  }]
  ingress = {
    enabled = true
  }
  domain_suffix = var.domain_suffix
}
