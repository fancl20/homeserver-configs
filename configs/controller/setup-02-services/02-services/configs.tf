variable "local_domain_suffix" {
  type = string
  default = "local.d20.fan"
}

provider "kubernetes" {}

provider "helm" {}

provider "vault" {}

provider "google" {
  project = "home-servers-275405"
  region = "australia-southeast1"
}