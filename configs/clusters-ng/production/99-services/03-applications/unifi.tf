resource "random_password" "unifi_db_root" {
  length = 32
  special = true
}

resource "random_password" "unifi_db_unifi" {
  length = 32
  special = true
}

resource "kubernetes_secret" "unifi" {
  metadata {
    name      = "unifi"
    namespace = "default"
  }
  data = {
    MONGO_INITDB_ROOT_USERNAME = "root"
    MONGO_INITDB_ROOT_PASSWORD = random_password.unifi_db_root.result
    MONGO_USER = "unifi"
    MONGO_PASS = random_password.unifi_db_unifi.result
    MONGO_DBNAME = "unifi"
    MONGO_AUTHSOURCE = "admin"
  }
}

