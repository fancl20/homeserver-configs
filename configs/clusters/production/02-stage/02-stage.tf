terraform {
  backend "gcs" {
    bucket = "0c9cfd1d-dc77-43e6-9131-d5535a91d844"
    prefix = "terraform/state/clusters-ng/production/02-stage"
  }
}

provider "google" {
  project = "home-servers-275405"
  region  = "australia-southeast1"
}

provider "vault" {}

module "cert_manager" {
  source = "./cert-manager"
}

module "vault" {
  source = "./vault"
}
