resource "google_service_account" "vault_storage" {
  account_id   = "vault-storage"
  display_name = "vault-storage"
  description  = "Vault Google Cloud Auto Unseal"
}

resource "google_project_iam_member" "vault_storage" {
  project = google_service_account.vault_storage.project
  role    = each.key
  member  = "serviceAccount:${google_service_account.vault_storage.email}"
  for_each = toset([
    "roles/cloudkms.viewer",
    "roles/cloudkms.cryptoKeyEncrypterDecrypter",
    "roles/storage.objectUser",
  ])
}

resource "google_service_account_key" "vault_storage" {
  service_account_id = google_service_account.vault_storage.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

resource "kubernetes_secret_v1" "vault_storage_key" {
  metadata {
    name      = "vault-storage-key"
    namespace = "vault"
  }
  data = {
    "key.json" = base64decode(google_service_account_key.vault_storage.private_key)
  }
}

resource "google_kms_key_ring" "vault_unseal" {
  name     = "vault-unseal"
  location = "australia-southeast1"
}

resource "google_kms_crypto_key" "vault_unseal" {
  name            = "vault-unseal"
  key_ring        = google_kms_key_ring.vault_unseal.id
  rotation_period = "7776000s"
  lifecycle {
    prevent_destroy = true
  }
}
