data "bitwarden-secrets_secret" "immich_db_password" {
  id = "dfd4c22a-3a6a-46e5-abe9-b49b0074b62b"
}

# NFS Persistent Volume для фото
resource "kubernetes_persistent_volume" "immich_photos_nfs" {
  metadata {
    name = "immich-photos-nfs"
  }
  spec {
    # Порожній storage_class_name потрібен для того, щоб Kubernetes не намагався
    # використати дефолтний динамічний StorageClass (напр. Longhorn),
    # а напряму прив'язав PVC до цього статичного NFS-тому з існуючими даними.
    storage_class_name = "manual"
    capacity = {
      storage = "5Ti"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    persistent_volume_source {
      nfs {
        path   = "/torrent"
        server = "192.168.0.21"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "immich_photos_nfs" {
  metadata {
    name      = "immich-photos-nfs"
    namespace = "default"
  }
  spec {
    # Порожній storage_class_name гарантує прив'язку саме до статичного PV,
    # дозволяючи змонтувати існуючу теку /torrent без створення нових підтек.
    storage_class_name = "manual"
    access_modes       = ["ReadWriteMany"]
    resources {
      requests = {
        storage = "5Ti"
      }
    }
    volume_name = kubernetes_persistent_volume.immich_photos_nfs.metadata[0].name
  }
}

# Секрет з паролем до БД для CNPG
resource "kubernetes_secret" "immich_db_password_cnpg" {
  metadata {
    name      = "immich-db-password"
    namespace = "cnpg-system"
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "immich"
    password = data.bitwarden-secrets_secret.immich_db_password.value
  }
}

# Створення ролі в shared-db
resource "kubernetes_manifest" "immich_role" {
  depends_on = [kubernetes_secret.immich_db_password_cnpg]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "DatabaseRole"
    metadata = {
      name      = "immich"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "immich"
      login = true
      passwordSecret = {
        name = kubernetes_secret.immich_db_password_cnpg.metadata[0].name
      }
    }
  }
}

# Створення бази даних в shared-db
resource "kubernetes_manifest" "immich_database" {
  depends_on = [kubernetes_manifest.immich_role]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"
    metadata = {
      name      = "immich"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "immich"
      owner = "immich"
      extensions = [
        {
          name = "vector"
        },
        {
          name = "cube"
        },
        {
          name = "earthdistance"
        }
      ]
    }
  }
}

resource "helm_release" "immich" {
  name            = "immich"
  repository      = "https://immich-app.github.io/immich-charts"
  chart           = "immich"
  namespace       = "default"
  upgrade_install = true

  values = [
    templatefile("${path.module}/helm_values/immich.yaml", {
      redis_password = data.bitwarden-secrets_secret.shared_redis.value,
      db_password    = data.bitwarden-secrets_secret.immich_db_password.value
    })
  ]

  depends_on = [
    kubernetes_persistent_volume_claim.immich_photos_nfs,
    kubernetes_manifest.immich_database
  ]
}
