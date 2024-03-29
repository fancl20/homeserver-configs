terraform {
  backend "gcs" {
    bucket = "0c9cfd1d-dc77-43e6-9131-d5535a91d844"
    prefix = "terraform/state/01-services"
  }
}

module "services" {
  source         = "./services"
  domain_suffix  = var.local_domain_suffix
  domain_tls_ref = var.local_domain_tls_ref
  dns_static_ip  = "192.168.1.3"
}
