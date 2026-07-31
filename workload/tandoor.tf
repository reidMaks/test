data "bitwarden-secrets_secret" "tandoor_db_password" {
  id = "2391cced-7e70-4ef1-a5d4-b4770084477e"
}

data "bitwarden-secrets_secret" "tandoor_fdc_api_key" {
  id = "ac2a25c3-0cc8-4062-9bb2-b47700849f84"
}

data "bitwarden-secrets_secret" "tandoor_secret_key" {
  id = "f228cbb7-5220-4678-a5bb-b4770083f01f"
}

resource "kubernetes_secret" "tandoor" {
  metadata {
    name      = "tandoor-secrets"
    namespace = "default"
  }

  data = {
    SECRET_KEY        = data.bitwarden-secrets_secret.tandoor_secret_key.value
    POSTGRES_PASSWORD = data.bitwarden-secrets_secret.tandoor_db_password.value
    FDC_API_KEY       = data.bitwarden-secrets_secret.tandoor_fdc_api_key.value
  }
}

resource "kubernetes_persistent_volume" "tandoor_mediafiles_s3" {
  metadata {
    name = "tandoor-mediafiles-s3"
  }
  spec {
    capacity = {
      storage = "1Gi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "s3-rclone"
    persistent_volume_source {
      csi {
        driver        = "csi-rclone"
        volume_handle = "tandoor-mediafiles-s3"
        volume_attributes = {
          remote     = "s3"
          remotePath = "kms-lab-data/tandoor-mediafiles"
        }
        node_publish_secret_ref {
          name      = "oci-s3-rclone-config"
          namespace = "kube-system"
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "tandoor_mediafiles_s3" {
  metadata {
    name      = "tandoor-mediafiles-s3"
    namespace = "default"
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "s3-rclone"
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    volume_name = kubernetes_persistent_volume.tandoor_mediafiles_s3.metadata[0].name
  }
}

resource "helm_release" "tandoor" {
  name            = "tandoor"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/tandoor.yaml")
  ]

  depends_on = [
    kubernetes_secret.tandoor,
    kubernetes_persistent_volume_claim.tandoor_mediafiles_s3
  ]
}

resource "kubernetes_secret" "tandoor_db_password_cnpg" {
  metadata {
    name      = "tandoor-db-password"
    namespace = "cnpg-system"
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "tandoor"
    password = data.bitwarden-secrets_secret.tandoor_db_password.value
  }
}

resource "kubernetes_manifest" "tandoor_role" {
  depends_on = [kubernetes_secret.tandoor_db_password_cnpg]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "DatabaseRole"
    metadata = {
      name      = "tandoor"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "tandoor"
      login = true
      passwordSecret = {
        name = kubernetes_secret.tandoor_db_password_cnpg.metadata[0].name
      }
    }
  }
}

resource "kubernetes_manifest" "tandoor_database" {
  depends_on = [kubernetes_manifest.tandoor_role]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"
    metadata = {
      name      = "db-recipes"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "db_recipes"
      owner = "tandoor"
    }
  }
}
