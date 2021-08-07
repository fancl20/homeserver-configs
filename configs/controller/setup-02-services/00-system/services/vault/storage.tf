resource "kubernetes_storage_class" "vault_storage" {
  metadata {
    name = "vault-storage"
  }
  storage_provisioner = "kubernetes.io/no-provisioner"
  reclaim_policy = "Retain"
  volume_binding_mode = "WaitForFirstConsumer"
}

resource "kubernetes_persistent_volume" "vault_storage" {
  metadata {
    name = "vault-storage"
  }
  spec {
    capacity = {
      storage = "10Gi"
    }
    access_modes = ["ReadWriteOnce"]
    volume_mode = "Filesystem"
    storage_class_name = kubernetes_storage_class.vault_storage.metadata[0].name
    persistent_volume_source {
      local {
        path = "/mnt/vault"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key = "kubernetes.io/hostname"
            operator = "In"
            values = [ "homeserver-controller" ]
          }
        }
      }
    }
  }
}