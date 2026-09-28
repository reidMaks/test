# ==============================================================================
# MAILPIT: SMTP Catcher & Email Testing Tool (for APN & CI preview environments)
# Runs in-memory with emptyDir (0 MB Longhorn persistent storage required)
# ==============================================================================

resource "kubernetes_deployment" "mailpit" {
  metadata {
    name      = "mailpit"
    namespace = kubernetes_namespace.apn.metadata[0].name
    labels = {
      app = "mailpit"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "mailpit"
      }
    }

    template {
      metadata {
        labels = {
          app = "mailpit"
        }
      }

      spec {
        node_selector = {
          "topology.kubernetes.io/zone" = "home"
        }

        container {
          name  = "mailpit"
          image = "axllent/mailpit:v1.31.2"

          env {
            name  = "MP_SMTP_BIND_ADDR"
            value = "0.0.0.0:1025"
          }
          env {
            name  = "MP_UI_BIND_ADDR"
            value = "0.0.0.0:8025"
          }
          env {
            name  = "MP_MAX_MESSAGES"
            value = "500"
          }
          env {
            name  = "MP_DATABASE"
            value = "/data/mailpit.db"
          }

          port {
            name           = "smtp"
            container_port = 1025
            protocol       = "TCP"
          }

          port {
            name           = "http"
            container_port = 8025
            protocol       = "TCP"
          }

          volume_mount {
            name       = "mailpit-data"
            mount_path = "/data"
          }

          startup_probe {
            http_get {
              path = "/livez"
              port = 8025
            }
            initial_delay_seconds = 2
            period_seconds        = 5
            failure_threshold     = 12
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 8025
            }
            period_seconds = 10
          }

          liveness_probe {
            http_get {
              path = "/livez"
              port = 8025
            }
            period_seconds = 20
          }

          resources {
            requests = {
              cpu    = "20m"
              memory = "32Mi"
            }
            limits = {
              memory = "128Mi"
            }
          }
        }

        volume {
          name = "mailpit-data"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "mailpit" {
  metadata {
    name      = "mailpit"
    namespace = kubernetes_namespace.apn.metadata[0].name
    labels = {
      app = "mailpit"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "mailpit"
    }

    port {
      name        = "smtp"
      port        = 1025
      target_port = 1025
      protocol    = "TCP"
    }

    port {
      name        = "http"
      port        = 8025
      target_port = 8025
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_ingress_v1" "mailpit" {
  metadata {
    name      = "mailpit"
    namespace = kubernetes_namespace.apn.metadata[0].name
    annotations = {
      "gatus.io/status" = "[STATUS] == 200"
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "mailpit.kms-lab.in.ua"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.mailpit.metadata[0].name
              port {
                number = 8025
              }
            }
          }
        }
      }
    }
  }
}
