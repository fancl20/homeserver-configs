variable "name" {
  type = string
}

variable "deployment" {}
variable "serviceAccount" {
  default = {}
}
variable "services" {
  default = []
}
variable "ingress" {
  default = {}
}
variable "domain_suffix" {
  default = ""
}
variable "vault_injector" {
  type = object({
    role    = string
    secrets = map(object({ path = string, template = string }))
  })
  default = { role = "", secrets = {} }
}

module "vault_injector" {
  source  = "../vault-injector"
  role    = var.vault_injector.role
  secrets = var.vault_injector.secrets
}

locals {
  annotations = merge(
    module.vault_injector.annotations,
    lookup(var.deployment, "podAnnotations", {})
  )
}

resource "helm_release" "service" {
  name  = var.name
  chart = "${path.module}/service-chart"
  values = [
    yamlencode({ deployment = merge(var.deployment, { "podAnnotations" : local.annotations }) }),
    yamlencode({ serviceAccount = var.serviceAccount }),
    yamlencode({ services = [for k, v in var.services : merge({ "name" : k }, v)] }),
    yamlencode({ ingress = var.ingress }),
    yamlencode({ domainSuffix = var.domain_suffix }),
  ]

  lifecycle {
    ignore_changes = [chart]
  }
}
