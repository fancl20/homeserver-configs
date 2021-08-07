resource "kubernetes_cluster_role" "external_dns" {
  metadata {
    name = "external-dns"
  }
  rule {
    api_groups = [""]
    resources  = ["services", "endpoints", "pods"]
    verbs      = ["get", "watch", "list"]
  }
  rule {
    api_groups = ["extensions", "networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "watch", "list"]
  }
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["list"]
  }
}

data "kubernetes_service_account" "external_dns" {
  metadata {
    name = "external-dns"
  }
  depends_on = [module.external_dns]
}

resource "kubernetes_cluster_role_binding" "external_dns" {
  metadata {
    name = "external-dns"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "external-dns"
  }
  subject {
    kind      = "ServiceAccount"
    name      = data.kubernetes_service_account.external_dns.metadata[0].name
    namespace = data.kubernetes_service_account.external_dns.metadata[0].namespace
  }
}

module "external_dns" {
  source = "../modules/general-service"
  name   = "external-dns"
  deployment = {
    image = {
      repository = "k8s.gcr.io/external-dns/external-dns"
      tag        = "v0.8.0"
    }
    command = ["/bin/sh"]
    args = ["-e", "-c", <<-EOT
      source /vault/secrets/env && /bin/external-dns \
        --registry=txt \
        --txt-prefix=external-dns- \
        --txt-owner-id=k8s \
        --provider=rfc2136 \
        --rfc2136-host=bind9.default \
        --rfc2136-port=53 \
        --rfc2136-zone=local.d20.fan \
        --rfc2136-tsig-keyname=externaldns-key \
        --rfc2136-tsig-axfr \
        --source=service \
        --source=ingress \
        --domain-filter=local.d20.fan
      EOT
    ]
    resources = {
      requests = { memory = "32Mi", cpu = "100m" }
      limits   = { memory = "64Mi", cpu = "200m" }
    }
  }
  vault_injector = {
    role = "homeserver"
    secrets = {
      env = {
        path     = "homeserver/data/bind9"
        template = <<-EOT
          {{ with secret "homeserver/data/bind9" -}}
          export EXTERNAL_DNS_RFC2136_TSIG_SECRET="{{ .Data.data.externaldns_key_secret }}"
          export EXTERNAL_DNS_RFC2136_TSIG_SECRET_ALG="{{ .Data.data.externaldns_key_algorithm }}"
          {{- end }}
        EOT
      }
    }
  }
}