resource "kubernetes_storage_class" "mass_storage" {
  metadata {
    name = "mass-storage"
  }
  storage_provisioner = "kubernetes.io/no-provisioner"
  reclaim_policy      = "Retain"
  volume_binding_mode = "WaitForFirstConsumer"
}

resource "kubernetes_persistent_volume" "mass_storage" {
  metadata {
    name = "mass-storage"
  }
  spec {
    capacity = {
      storage = "6Ti"
    }
    access_modes       = ["ReadWriteOnce"]
    volume_mode        = "Filesystem"
    storage_class_name = kubernetes_storage_class.mass_storage.metadata[0].name
    persistent_volume_source {
      local {
        path = "/mnt/data"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = ["homeserver-controller"]
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "mass_storage" {
  metadata {
    name = "mass-storage"
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.mass_storage.metadata[0].name
    volume_name        = kubernetes_persistent_volume.mass_storage.metadata[0].name
    resources {
      requests = {
        storage = "6Ti"
      }
    }
  }
}

locals {
  mass_storage_volume = {
    name = "data"
    persistentVolumeClaim = {
      claimName = kubernetes_persistent_volume_claim.mass_storage.metadata[0].name
    }
  }
}

# vault-storage-backup refer to the same place as vault-storage. A better
# solution to eliminate sharing PersistentVolume is using vault's builtin
# backup - if available.
data "kubernetes_storage_class" "vault_storage" {
  metadata {
    name = "vault-storage"
  }
}

resource "kubernetes_persistent_volume" "vault_storage_backup" {
  metadata {
    name = "vault-storage-backup"
  }
  spec {
    capacity = {
      storage = "10Gi"
    }
    access_modes       = ["ReadWriteOnce"]
    volume_mode        = "Filesystem"
    storage_class_name = data.kubernetes_storage_class.vault_storage.metadata[0].name
    persistent_volume_source {
      local {
        path = "/mnt/vault"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = ["homeserver-controller"]
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "vault_storage_backup" {
  metadata {
    name = "vault-storage-backup"
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.vault_storage.metadata[0].name
    volume_name        = kubernetes_persistent_volume.vault_storage_backup.metadata[0].name
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}
