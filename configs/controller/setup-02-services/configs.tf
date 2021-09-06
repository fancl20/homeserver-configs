variable "local_domain_suffix" {
  type    = string
  default = "local.d20.fan"
}

variable "local_domain_tls_ref" {
  type    = string
  default = "local-tls"
}

provider "kubernetes" {
  experiments {
    manifest_resource = true
  }
}

provider "helm" {}

provider "vault" {}

provider "google" {
  project = "home-servers-275405"
  region  = "australia-southeast1"
}
