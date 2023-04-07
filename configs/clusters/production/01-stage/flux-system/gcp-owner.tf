resource "google_service_account" "tf_controller" {
  account_id   = "tf-controller"
  display_name = "tf-controller"
  description  = "Flux2 Terraform Controller"
}

resource "google_project_iam_member" "tf_controller" {
  project = "home-servers-275405"
  role    = each.key
  member  = "serviceAccount:${google_service_account.tf_controller.email}"
  for_each = toset([
    "roles/owner",
  ])
}

resource "google_service_account_key" "tf_controller" {
  service_account_id = google_service_account.tf_controller.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

resource "kubernetes_secret" "tf_controller_key" {
  metadata {
    name      = "tf-controller-key"
    namespace = "flux-system"
  }
  data = {
    "GOOGLE_CREDENTIALS" = base64decode(google_service_account_key.tf_controller.private_key)
  }
}
