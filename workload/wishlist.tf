# ==========================================
# wishlist (via bjw-s app-template chart)
# ==========================================

resource "helm_release" "wishlist" {
  name            = "wishlist"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    templatefile("${path.module}/helm_values/wishlist.yaml", {
      oci_s3_endpoint = data.terraform_remote_state.infra.outputs.oci_s3_endpoint
    }),
    templatefile("${path.module}/helm_values/litestream_sidecar.yaml.tpl", {
      controller_name = "main"
      db_path         = "/usr/src/app/data/prod.db"
      s3_path         = "s3://kms-lab-data/wishlist-db"
      oci_s3_endpoint = data.terraform_remote_state.infra.outputs.oci_s3_endpoint
      secret_name     = "litestream-s3"
    })
  ]

  depends_on = [kubernetes_persistent_volume_claim.wishlist_uploads_s3, kubernetes_secret.litestream_s3]
}

resource "kubernetes_persistent_volume" "wishlist_uploads_s3" {
  metadata {
    name = "wishlist-uploads-s3"
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
        volume_handle = "wishlist-uploads-s3"
        volume_attributes = {
          remote     = "s3"
          remotePath = "kms-lab-data/wishlist-uploads"
        }
        node_publish_secret_ref {
          name      = "oci-s3-rclone-config"
          namespace = "kube-system"
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "wishlist_uploads_s3" {
  metadata {
    name      = "wishlist-uploads-s3"
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
    volume_name = kubernetes_persistent_volume.wishlist_uploads_s3.metadata[0].name
  }
}
