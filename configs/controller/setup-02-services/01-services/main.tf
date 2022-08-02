terraform {
  backend "gcs" {
    bucket = "0c9cfd1d-dc77-43e6-9131-d5535a91d844"
    prefix = "terraform/state/01-services"
  }
}

module "vault" {
  source = "./policies/vault"
}

module "metallb" {
  source = "./policies/metallb"
}

module "vault_restart" {
  source  = "./modules/vault-restart"
  trigger = module.vault.restart_trigger
}

resource "kubernetes_manifest" "multus_macvlan" {
  manifest = {
    apiVersion = "k8s.cni.cncf.io/v1"
    kind       = "NetworkAttachmentDefinition"
    metadata = {
      "name"      = "macvlan"
      "namespace" = "default"
    }
    spec = {
      config = jsonencode({
        cniVersion = "0.4.0"
        plugins = [
          {
            type         = "macvlan"
            capabilities = { "ips" = true }
            master       = "enp2s0"
            mode         = "bridge"
            ipam = {
              type = "static"
              routes = [
                { dst = "0.0.0.0/0", gw = "192.168.1.1" }
              ]
            }
          },
          {
            type         = "tuning"
            capabilities = { mac = true }
          }
        ]
      })
    }
  }
}

module "services" {
  source         = "./services"
  domain_suffix  = var.local_domain_suffix
  domain_tls_ref = var.local_domain_tls_ref
  dns_static_ip  = "192.168.1.3"
  depends_on     = [module.vault_restart]
}
