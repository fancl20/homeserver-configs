resource "google_service_account" "vault_kms" {
  account_id   = "vault-kms"
  display_name = "vault-kms"
  description  = "Vault Google Cloud Auto Unseal"
}

resource "google_project_iam_member" "vault_kms" {
  role   = each.key
  member = "serviceAccount:${google_service_account.vault_kms.email}"
  for_each = toset([
    "roles/cloudkms.cryptoKeyEncrypterDecrypter",
  ])
}

resource "google_service_account_key" "vault_kms" {
  service_account_id = google_service_account.vault_kms.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

resource "kubernetes_secret" "vault_kms_key" {
  metadata {
    name      = "vault-kms-key"
    namespace = "vault"
  }
  data = {
    "key.json" = base64decode(google_service_account_key.vault_kms.private_key)
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