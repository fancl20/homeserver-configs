resource "random_password" "n8n_db" {
  length = 32
  special = false
}

resource "kubernetes_secret_v1" "n8n" {
  metadata {
    name      = "n8n"
    namespace = "default"
  }
  data = {
    POSTGRES_USER          = "n8n"
    POSTGRES_PASSWORD      = random_password.n8n_db.result
    DB_POSTGRESDB_USER      = "n8n"
    DB_POSTGRESDB_PASSWORD  = random_password.n8n_db.result
  }
}
