resource "google_service_account" "vault_gcp" {
  account_id   = "vault-gcp"
  display_name = "vault-gcp"
  description  = "Vault Google Cloud Secrete Backend"
}

resource "google_project_iam_member" "vault_gcp" {
  role   = each.key
  member = "serviceAccount:${google_service_account.vault_gcp.email}"
  for_each = toset([
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountKeyAdmin",
    "roles/resourcemanager.projectIamAdmin",
  ])
}

resource "google_service_account_key" "vault_gcp" {
  service_account_id = google_service_account.vault_gcp.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

resource "vault_gcp_secret_backend" "gcp" {
  credentials               = base64decode(google_service_account_key.vault_gcp.private_key)
  default_lease_ttl_seconds = 3600
}

locals {
  gcp_project = google_service_account.vault_gcp.project
}

resource "vault_gcp_secret_roleset" "certbot" {
  backend     = vault_gcp_secret_backend.gcp.path
  roleset     = "certbot"
  secret_type = "service_account_key"
  project     = local.gcp_project
  token_scopes = [
    "https://www.googleapis.com/auth/ndev.clouddns.readwrite",
    "https://www.googleapis.com/auth/cloud-platform.read-only",
  ]

  binding {
    resource = "//cloudresourcemanager.googleapis.com/projects/${local.gcp_project}"
    roles = [
      "roles/dns.admin",
    ]
  }
}