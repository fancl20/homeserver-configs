module "jellyfin" {
  source = "../modules/general-service"
  name = "jellyfin"
  deployment = {
    image = {
      repository = "ghcr.io/linuxserver/jellyfin"
    }
    env = [
      { name = "TZ", value = "Australia/Sydney" },
      { name = "PUID", value = "0" },
      { name = "GUID", value = "0" },
    ]
    volumeMounts = [
      { name = "data", mountPath = "/config", subPath = "jellyfin/config" },
      { name = "data", mountPath = "/shared", subPath = "shared" },
    ]
    volumes = [
      local.mass_storage_volume,
    ]
  }
  services = {
    jellyfin = {
      ports = [
        { name = "webui", protocol = "TCP", port = 80, targetPort = 8096 },
      ]
    }
  }
  ingress = {
    enabled = true
  }
  domain_suffix = var.domain_suffix
}