terraform {
  backend "gcs" {
    bucket = "0c9cfd1d-dc77-43e6-9131-d5535a91d844"
    prefix = "terraform/state/00-system"
  }
}

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

module "metallb" {
  source = "./services/metallb"
}

module "ingress_nginx" {
  source         = "./services/ingress-nginx"
  domain_tls_ref = var.local_domain_tls_ref
}

# Create an ingress for default-http-backend. It will wait until ingress ready,
# which can be depended on by other services.
module "default_http_backend" {
  source     = "./services/default-http-backend"
  depends_on = [module.ingress_nginx]
}

module "vault" {
  source        = "./services/vault"
  domain_suffix = var.local_domain_suffix
  depends_on = [
    module.default_http_backend,
    google_project_service.services,
  ]
}
