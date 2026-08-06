data "bitwarden-secrets_secret" "monobank_token" {
  id = "3f16903e-c45e-47b6-9716-b478016cd900"
}

resource "helm_release" "actualbudget" {
  name            = "actualbudget"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    templatefile("${path.module}/actualbudget/values.yaml", {
      addon_py       = file("${path.module}/actualbudget/addon.py")
      monobank_token = data.bitwarden-secrets_secret.monobank_token.value
      s3_endpoint    = local.minio_s3_endpoint
    }),
    templatefile("${path.module}/helm_values/litestream_sidecar.yaml.tpl", {
      controller_name = "main"
      db_path         = "" # Leave empty to skip 01-litestream-restore initContainer
      secret_name     = "litestream-s3"
    })
  ]

  depends_on = [kubernetes_persistent_volume_claim.actualbudget_files_s3, kubernetes_persistent_volume_claim.actualbudget_db_s3, kubernetes_secret.litestream_s3]
}

resource "kubernetes_persistent_volume" "actualbudget_files_s3" {
  metadata {
    name = "actualbudget-files-s3"
  }
  spec {
    capacity = {
      storage = "200Mi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "s3-rclone"
    persistent_volume_source {
      csi {
        driver        = "csi-rclone"
        volume_handle = "actualbudget-files-s3"
        volume_attributes = {
          remote     = "s3"
          remotePath = "kms-lab-data/actualbudget-files"
        }
        node_publish_secret_ref {
          name      = "oci-s3-rclone-config"
          namespace = "kube-system"
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "actualbudget_files_s3" {
  metadata {
    name      = "actualbudget-files-s3"
    namespace = "default"
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "s3-rclone"
    resources {
      requests = {
        storage = "200Mi"
      }
    }
    volume_name = kubernetes_persistent_volume.actualbudget_files_s3.metadata[0].name
  }
}

resource "kubernetes_persistent_volume" "actualbudget_db_s3" {
  metadata {
    name = "actualbudget-db-s3"
  }
  spec {
    capacity = {
      storage = "200Mi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "s3-rclone"
    persistent_volume_source {
      csi {
        driver        = "csi-rclone"
        volume_handle = "actualbudget-db-s3"
        volume_attributes = {
          remote     = "s3"
          remotePath = "kms-lab-data/actualbudget-db"
        }
        node_publish_secret_ref {
          name      = "oci-s3-rclone-config"
          namespace = "kube-system"
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "actualbudget_db_s3" {
  metadata {
    name      = "actualbudget-db-s3"
    namespace = "default"
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "s3-rclone"
    resources {
      requests = {
        storage = "200Mi"
      }
    }
    volume_name = kubernetes_persistent_volume.actualbudget_db_s3.metadata[0].name
  }
}
