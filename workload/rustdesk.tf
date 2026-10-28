# ============================================================
# RustDesk Self-Hosted Server (hbbs + hbbr + rustdesk-api)
# ============================================================

resource "random_password" "rustdesk_jwt_key" {
  length  = 32
  special = false
}

resource "random_password" "rustdesk_admin_password" {
  length  = 24
  special = false
}

resource "kubernetes_secret" "rustdesk_api_secret" {
  metadata {
    name      = "rustdesk-api-secret"
    namespace = "default"
  }

  data = {
    RUSTDESK_API_JWT_KEY = random_password.rustdesk_jwt_key.result
    RUSTDESK_ADMIN_PWD   = random_password.rustdesk_admin_password.result
    OIDC_CLIENT_SECRET   = random_password.authentik_rustdesk_secret.result
  }
}

resource "kubernetes_persistent_volume" "rustdesk_keys_s3" {
  metadata {
    name = "rustdesk-keys-s3"
  }
  spec {
    capacity = {
      storage = "20Mi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "s3-rclone"
    persistent_volume_source {
      csi {
        driver        = "csi-rclone"
        volume_handle = "rustdesk-keys-s3"
        volume_attributes = {
          remote     = "s3"
          remotePath = "kms-lab-data/rustdesk-keys"
        }
        node_publish_secret_ref {
          name      = "oci-s3-rclone-config"
          namespace = "kube-system"
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "rustdesk_keys_s3" {
  metadata {
    name      = "rustdesk-keys-s3"
    namespace = "default"
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "s3-rclone"
    resources {
      requests = {
        storage = "20Mi"
      }
    }
    volume_name = kubernetes_persistent_volume.rustdesk_keys_s3.metadata[0].name
  }
}

resource "helm_release" "rustdesk" {
  name            = "rustdesk"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = local.app_template_version
  namespace       = "default"
  upgrade_install = true

  values = [
    templatefile("${path.module}/helm_values/litestream_sidecar.yaml.tpl", {
      controller_name = "main"
      db_path         = "/root/db_v2.sqlite3"
      db_dir          = ""
      db_path_exact   = "/root/db_v2.sqlite3"
      bucket_path     = "rustdesk-db"
      release_name    = "rustdesk"
      secret_name     = "litestream-s3"
    }),
    file("${path.module}/helm_values/rustdesk.yaml")
  ]

  depends_on = [
    kubernetes_persistent_volume_claim.rustdesk_keys_s3,
    kubernetes_secret.litestream_s3,
    kubernetes_secret.rustdesk_api_secret
  ]
}
