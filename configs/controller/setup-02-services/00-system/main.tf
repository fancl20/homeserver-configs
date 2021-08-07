terraform {
  backend "gcs" {
    bucket = "0c9cfd1d-dc77-43e6-9131-d5535a91d844"
    prefix = "terraform/state/00-system"
  }
}

module "metallb" {
  source = "./services/metallb"
}

module "ingress_nginx" {
  source = "./services/ingress-nginx"
}

# Create an ingress for default-http-backend. It will wait until ingress ready,
# which can be depended on by other services.
module "default_http_backend" {
  source     = "./services/default-http-backend"
  depends_on = [module.ingress_nginx]
}

module "vault" {
  source              = "./services/vault"
  local_domain_suffix = var.local_domain_suffix
  depends_on          = [module.default_http_backend]
}
