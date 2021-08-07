resource "google_service_account" "vault_gcp" {
  account_id = "vault-gcp"
  display_name = "vault-gcp"
  description = "Vault Google Cloud Secrete Backend"
}

resource "google_project_iam_member" "vault_gcp" {
  role = each.key
  member = "serviceAccount:${google_service_account.vault_gcp.email}"
  for_each = toset([
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountKeyAdmin",
    "roles/cloudkms.admin",
    "roles/cloudkms.cryptoKeyEncrypterDecrypter",
    "roles/dns.admin",
  ])
}

resource "google_service_account_key" "vault_gcp" {
  service_account_id = google_service_account.vault_gcp.name
  public_key_type = "TYPE_X509_PEM_FILE"
}

resource "vault_gcp_secret_backend" "gcp" {
  credentials = base64decode(google_service_account_key.vault_gcp.private_key)
}