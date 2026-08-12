data "bitwarden-secrets_secret" "freelingo_env" {
  id = "2c68e061-6086-4507-b3d8-b49700b99d71"
}

locals {
  env = jsondecode(data.bitwarden-secrets_secret.freelingo_env.value)
}

resource "kubernetes_secret" "freelingo" {
  metadata {
    name      = "freelingo-secrets"
    namespace = "default"
  }

  data = {
    POSTGRES_DB       = "freelingo"
    POSTGRES_USER     = "freelingo"
    POSTGRES_PASSWORD = local.env["POSTGRES_PASSWORD"]
    REDIS_PASSWORD    = local.env["REDIS_PASSWORD"]
    SECRET_KEY        = local.env["SECRET_KEY"]
    OPENAI_API_KEY    = data.bitwarden-secrets_secret.open_router_api_key.value
  }
}

resource "kubernetes_persistent_volume" "freelingo_data_s3" {
  metadata {
    name = "freelingo-data-s3"
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
        volume_handle = "freelingo-data-s3"
        volume_attributes = {
          remote     = "s3"
          remotePath = "kms-lab-data/freelingo-data"
        }
        node_publish_secret_ref {
          name      = "oci-s3-rclone-config"
          namespace = "kube-system"
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "freelingo_data_s3" {
  metadata {
    name      = "freelingo-data-s3"
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
    volume_name = kubernetes_persistent_volume.freelingo_data_s3.metadata[0].name
  }
}

resource "helm_release" "freelingo" {
  name            = "freelingo"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    templatefile("${path.module}/freelingo/values.yaml", {
      redis_password = data.bitwarden-secrets_secret.shared_redis.value
      db_password    = local.env["POSTGRES_PASSWORD"]
    })
  ]

  depends_on = [
    kubernetes_secret.freelingo,
    kubernetes_persistent_volume_claim.freelingo_data_s3
  ]
}

resource "kubernetes_config_map" "freelingo_patches" {
  metadata {
    name      = "freelingo-patches"
    namespace = "default"
  }

  data = {
    "auth.py"  = file("${path.module}/freelingo/auth.py")
    "admin.py" = file("${path.module}/freelingo/admin.py")
  }
}

resource "kubernetes_secret" "freelingo_db_password_cnpg" {
  metadata {
    name      = "freelingo-db-password"
    namespace = "cnpg-system"
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "freelingo"
    password = local.env["POSTGRES_PASSWORD"]
  }
}

resource "kubernetes_manifest" "freelingo_role" {
  depends_on = [kubernetes_secret.freelingo_db_password_cnpg]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "DatabaseRole"
    metadata = {
      name      = "freelingo"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "freelingo"
      login = true
      passwordSecret = {
        name = kubernetes_secret.freelingo_db_password_cnpg.metadata[0].name
      }
    }
  }
}

resource "kubernetes_manifest" "freelingo_database" {
  depends_on = [kubernetes_manifest.freelingo_role]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"
    metadata = {
      name      = "freelingo"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "freelingo"
      owner = "freelingo"
    }
  }
}
