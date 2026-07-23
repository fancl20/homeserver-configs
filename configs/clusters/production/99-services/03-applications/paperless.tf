resource "random_password" "paperless_secret_key" {
  length  = 64
  special = false
}

resource "kubernetes_secret_v1" "paperless" {
  metadata {
    name      = "paperless"
    namespace = "default"
  }
  data = {
    PAPERLESS_SECRET_KEY = random_password.paperless_secret_key.result
  }
}
