data "bitwarden-secrets_secret" "paperless_db_password" {
  id = "5c782528-6191-4718-a1bc-b4780128cdb2"
}

data "bitwarden-secrets_secret" "paperless_secret_key" {
  id = "be5332e6-a0fc-4d36-a2c9-b4780127d813"
}

resource "kubernetes_secret" "paperless" {
  metadata {
    name      = "paperless-secrets"
    namespace = "default"
  }

  data = {
    PAPERLESS_SECRET_KEY = data.bitwarden-secrets_secret.paperless_secret_key.value
    PAPERLESS_DBPASS     = data.bitwarden-secrets_secret.paperless_db_password.value
    POSTGRES_PASSWORD    = data.bitwarden-secrets_secret.paperless_db_password.value
  }
}

resource "kubernetes_persistent_volume" "paperless_media_s3" {
  metadata {
    name = "paperless-media-s3"
  }
  spec {
    capacity = {
      storage = "5Gi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "s3-rclone"
    persistent_volume_source {
      csi {
        driver        = "csi-rclone"
        volume_handle = "paperless-media-s3"
        volume_attributes = {
          remote     = "s3"
          remotePath = "kms-lab-data/paperless-media"
        }
        node_publish_secret_ref {
          name      = "oci-s3-rclone-config"
          namespace = "kube-system"
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "paperless_media_s3" {
  metadata {
    name      = "paperless-media-s3"
    namespace = "default"
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "s3-rclone"
    resources {
      requests = {
        storage = "5Gi"
      }
    }
    volume_name = kubernetes_persistent_volume.paperless_media_s3.metadata[0].name
  }
}

resource "helm_release" "paperless" {
  name            = "paperless"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/paperless.yaml")
  ]

  depends_on = [
    kubernetes_secret.paperless,
    kubernetes_persistent_volume_claim.paperless_media_s3
  ]
}

resource "kubernetes_secret" "paperless_db_password_cnpg" {
  metadata {
    name      = "paperless-db-password"
    namespace = "cnpg-system"
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "paperless"
    password = data.bitwarden-secrets_secret.paperless_db_password.value
  }
}

resource "kubernetes_manifest" "paperless_role" {
  depends_on = [kubernetes_secret.paperless_db_password_cnpg]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "DatabaseRole"
    metadata = {
      name      = "paperless"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "paperless"
      login = true
      passwordSecret = {
        name = kubernetes_secret.paperless_db_password_cnpg.metadata[0].name
      }
    }
  }
}

resource "kubernetes_manifest" "paperless_database" {
  depends_on = [kubernetes_manifest.paperless_role]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"
    metadata = {
      name      = "paperless"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "paperless"
      owner = "paperless"
    }
  }
}
