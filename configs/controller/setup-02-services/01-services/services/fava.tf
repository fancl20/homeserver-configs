module "fava" {
  source = "../modules/general-service"
  name   = "fava"
  deployment = {
    containers = [{
      image = "ghcr.io/fancl20/fava"
      args  = ["/usr/local/bin/fava", "--port", "5000", "/data/main.beancount"]
      env = [
        { name = "TZ", value = "Australia/Sydney" },
      ]
      volumeMounts = [
        { name = "data", mountPath = "/data", subPath = "workspaces/common/accounting" },
      ]
    }]
    volumes = [
      local.mass_storage_volume,
    ]
  }
  services = [{
    ports = [
      { name = "webui", protocol = "TCP", port = 80, targetPort = 5000 },
    ]
  }]
  ingress = {
    enabled = true
  }
  domain_suffix = var.domain_suffix
}
