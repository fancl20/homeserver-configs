resource "random_bytes" "bind9_secret" {
  length = 256
}

resource "kubernetes_secret" "bind9" {
  metadata {
    name      = "bind9"
    namespace = "default"
  }
  data = {
    "bind9_externaldns_key" = <<-EOT
     key bind9-externaldns {
        algorithm hmac-sha256;
        secret "${random_bytes.bind9_secret.base64}";
    };
    EOT
  }
}

resource "kubernetes_secret" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = "default"
  }
  data = {
    EXTERNAL_DNS_RFC2136_TSIG_SECRET_ALG = "hmac-sha256"
    EXTERNAL_DNS_RFC2136_TSIG_SECRET = random_bytes.bind9_secret.base64
  }
}
