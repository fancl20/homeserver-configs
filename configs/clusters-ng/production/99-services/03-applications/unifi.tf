resource "random_password" "unifi_db" {
  length = 32
  special = false
}

resource "kubernetes_secret" "unifi" {
  metadata {
    name      = "unifi"
    namespace = "default"
  }
  data = {
    MONGO_USER = "unifi"
    MONGO_PASS = random_password.unifi_db.result
    MONGO_DBNAME = "unifi"
  }
}

