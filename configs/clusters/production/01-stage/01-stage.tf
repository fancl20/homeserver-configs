terraform {
  backend "gcs" {
    bucket = "0c9cfd1d-dc77-43e6-9131-d5535a91d844"
    prefix = "terraform/state/clusters/production/01-stage"
  }
}

provider "google" {
  project = "home-servers-275405"
  region  = "australia-southeast1"
}

provider "kubernetes" {}

resource "google_project_service" "services" {
  service = each.key
  for_each = toset([
    "iam.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "dns.googleapis.com",
    "cloudkms.googleapis.com",
    "compute.googleapis.com",
  ])
}

module "flux_system" {
  source = "./flux-system"
  depends_on = [
    google_project_service.services,
  ]
}

module "vault" {
  source = "./vault"
  depends_on = [
    google_project_service.services,
  ]
}
