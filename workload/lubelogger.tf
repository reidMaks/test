# ==========================================
# LUBELOGGER (via bjw-s app-template chart)
# ==========================================

resource "random_password" "lubelogger_db_password" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "lubelogger_db_password_cnpg" {
  metadata {
    name      = "lubelogger-db-password"
    namespace = "cnpg-system"
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "lubelogger"
    password = random_password.lubelogger_db_password.result
  }
}

resource "kubernetes_manifest" "lubelogger_role" {
  depends_on = [kubernetes_secret.lubelogger_db_password_cnpg]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "DatabaseRole"
    metadata = {
      name      = "lubelogger"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "lubelogger"
      login = true
      passwordSecret = {
        name = kubernetes_secret.lubelogger_db_password_cnpg.metadata[0].name
      }
    }
  }
}

resource "kubernetes_manifest" "lubelogger_database" {
  depends_on = [kubernetes_manifest.lubelogger_role]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"
    metadata = {
      name      = "lubelogger"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "lubelogger"
      owner = "lubelogger"
    }
  }
}

resource "kubernetes_persistent_volume" "lubelogger_files_s3" {
  metadata {
    name = "lubelogger-files-s3"
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
        volume_handle = "lubelogger-files-s3"
        volume_attributes = {
          remote     = "s3"
          remotePath = "kms-lab-data/lubelogger-files"
        }
        node_publish_secret_ref {
          name      = "oci-s3-rclone-config"
          namespace = "kube-system"
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "lubelogger_files_s3" {
  metadata {
    name      = "lubelogger-files-s3"
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
    volume_name = kubernetes_persistent_volume.lubelogger_files_s3.metadata[0].name
  }
}

resource "kubernetes_secret" "lubelogger_env" {
  metadata {
    name      = "lubelogger-env"
    namespace = "default"
  }
  data = {
    # LubeLogger PostgreSQL connection string format
    POSTGRES_CONNECTION = "Server=shared-db-rw.cnpg-system.svc.cluster.local;Port=5432;Database=lubelogger;User Id=lubelogger;Password=${random_password.lubelogger_db_password.result};"
  }
}

resource "helm_release" "lubelogger" {
  name            = "lubelogger"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/lubelogger.yaml")
  ]

  depends_on = [
    kubernetes_persistent_volume_claim.lubelogger_files_s3,
    kubernetes_manifest.lubelogger_database,
    kubernetes_secret.lubelogger_env
  ]
}
