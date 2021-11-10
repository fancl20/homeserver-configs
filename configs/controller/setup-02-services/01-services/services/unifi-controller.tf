module "unifi_controller" {
  source = "../modules/general-service"
  name   = "unifi-controller"
  deployment = {
    image = {
      repository = "lscr.io/linuxserver/unifi-controller"
    }
    podAnnotations = {
      "k8s.v1.cni.cncf.io/networks" = jsonencode([
        {
          name    = "macvlan"
          ips     = ["192.168.1.246/24"]
          mac     = "26:1e:94:c2:23:41"
          gateway = ["192.168.1.1"]
        }
      ])
    }
    env = [
      { name = "TZ", value = "Australia/Sydney" },
      { name = "PUID", value = "0" },
      { name = "GUID", value = "0" },
    ]
    volumeMounts = [
      { name = "data", mountPath = "/config", subPath = "unifi-controller/config" },
    ]
    volumes = [
      local.mass_storage_volume,
    ]
  }
  services = {
    unifi-controller = {
      ports = [
        { name = "webui", protocol = "TCP", port = 443, targetPort = 8443 },
      ]
    }
  }
  ingress = {
    enabled = true
    annotations = {
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS"
    }
    hostname = "unifi"
    backend  = { port = 443 }
  }
  domain_suffix = var.domain_suffix
}
