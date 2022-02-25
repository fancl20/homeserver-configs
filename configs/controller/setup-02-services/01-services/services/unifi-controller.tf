module "unifi_controller" {
  source = "../modules/general-service"
  name   = "unifi-controller"
  deployment = {
    containers = [{
      image = "lscr.io/linuxserver/unifi-controller:latest"
      env = [
        { name = "TZ", value = "Australia/Sydney" },
        { name = "PUID", value = "0" },
        { name = "GUID", value = "0" },
      ]
      volumeMounts = [
        { name = "data", mountPath = "/config", subPath = "unifi-controller/config" },
      ]
    }]
    volumes = [
      local.mass_storage_volume,
    ]
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
  }
  services = [{
    ports = [
      { name = "webui", protocol = "TCP", port = 443, targetPort = 8443 },
    ]
  }]
  ingress = {
    enabled = true
    metadata = {
      annotations = {
        "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS"
      }
    }
    backend = { port = 443 }
  }
  hostname      = "unifi"
  domain_suffix = var.domain_suffix
}
