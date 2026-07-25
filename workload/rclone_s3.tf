# Читаємо конфіг Google Drive з Bitwarden
data "bitwarden-secrets_secret" "rclone_conf" {
  id = "0539e29c-5d1a-4ce6-b882-b49200b46dc5"
}

resource "kubernetes_secret" "rclone_config" {
  metadata {
    name      = "rclone-config"
    namespace = "longhorn-system"
  }
  data = {
    "rclone.conf" = data.bitwarden-secrets_secret.rclone_conf.value
  }
}

resource "kubernetes_deployment" "rclone_s3_gateway" {
  metadata {
    name      = "rclone-s3-gateway"
    namespace = "longhorn-system"
    labels = {
      app = "rclone-s3-gateway"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "rclone-s3-gateway"
      }
    }

    template {
      metadata {
        labels = {
          app = "rclone-s3-gateway"
        }
      }

      spec {
        # Жорстко прив'язуємо шлюз до OCI ноди для відмовостійкості
        node_selector = {
          "topology.kubernetes.io/zone" = "oci"
        }

        # Копіюємо конфіг з read-only Secret у записувану папку
        init_container {
          name    = "init-config"
          image   = "alpine:latest"
          command = ["sh", "-c", "cp /tmp/secret/rclone.conf /config/rclone/rclone.conf"]
          volume_mount {
            name       = "secret-volume"
            mount_path = "/tmp/secret"
          }
          volume_mount {
            name       = "config"
            mount_path = "/config/rclone"
          }
        }

        container {
          name  = "rclone"
          image = "rclone/rclone:latest"
          command = [
            "rclone",
            "serve",
            "s3",
            "gdrive:K8s-Backups",
            "--addr", "0.0.0.0:8080",
            "--vfs-cache-mode", "writes",
            "--vfs-cache-max-size", "2G",
            "--auth-key", "${data.bitwarden-secrets_secret.qobject_access_key.value},${data.bitwarden-secrets_secret.qobject_secret_key.value}"
          ]

          port {
            container_port = 8080
          }

          volume_mount {
            name       = "config"
            mount_path = "/config/rclone"
          }
          volume_mount {
            name       = "cache"
            mount_path = "/root/.cache/rclone"
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }

        volume {
          name = "secret-volume"
          secret {
            secret_name = kubernetes_secret.rclone_config.metadata[0].name
          }
        }
        volume {
          name = "config"
          empty_dir {}
        }
        volume {
          name = "cache"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "rclone_s3_gateway" {
  metadata {
    name      = "rclone-s3-gateway"
    namespace = "longhorn-system"
  }

  spec {
    selector = {
      app = "rclone-s3-gateway"
    }

    port {
      port        = 8080
      target_port = 8080
    }
  }
}
