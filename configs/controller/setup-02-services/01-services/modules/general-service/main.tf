variable "name" {
  type = string
}
variable "namespace" {
  type    = string
  default = "default"
}

variable "deployment" {
  default = {}
}
variable "service_account" {
  default = {}
}
variable "services" {
  default = []
}
variable "ingress" {
  default = {}
}

variable "hostname" {
  default = ""
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
  hostname = format("%s.%s", coalesce(var.hostname, var.name), trimprefix(var.domain_suffix, "."))
  selector_labels = {
    "app.kubernetes.io/name" = var.name
  }
}
