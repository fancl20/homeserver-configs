resource "random_password" "coder_db" {
  length = 32
  special = false
}

resource "kubernetes_secret" "coder" {
  metadata {
    name      = "coder-db"
    namespace = "coder"
  }
  data = {
    POSTGRES_USER = "coder"
    POSTGRES_PASSWORD = random_password.unifi_db.result
    url = "postgres://coder:${random_password.unifi_db.result}@coder-db.coder.svc.cluster.local:5432/coder?sslmode=disable"
  }
}

