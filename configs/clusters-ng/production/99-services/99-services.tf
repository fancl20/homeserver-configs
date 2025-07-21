terraform {
  backend "gcs" {
    bucket = "0c9cfd1d-dc77-43e6-9131-d5535a91d844"
    prefix = "terraform/state/clusters-ng/production/99-services"
  }
}

provider "kubernetes" {}

provider "random" {}

provider "vault" {}

module "infrastructure" {
  source = "./01-infrastructure"
}
