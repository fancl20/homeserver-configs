output "restart_trigger" {
  value = {
    vault_config_updater_secret = kubernetes_secret.vault_config_updater.metadata[0].resource_version
  }
}
