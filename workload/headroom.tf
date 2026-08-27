# ==========================================
# Headroom Proxy (LLM context compression)
# ==========================================

resource "kubernetes_deployment" "headroom" {
  metadata {
    name      = "headroom"
    namespace = "default"
    labels = {
      app = "headroom"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "headroom"
      }
    }

    template {
      metadata {
        labels = {
          app = "headroom"
        }
      }

      spec {
        container {
          name  = "headroom"
          image = "ghcr.io/headroomlabs-ai/headroom:latest"
          args  = ["--host", "0.0.0.0", "--port", "8787", "--log-file", "/dev/stdout"]

          port {
            container_port = 8787
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          env {
            name  = "ANTHROPIC_TARGET_API_URL"
            value = "https://api.anthropic.com"
          }
          env {
            name  = "OPENAI_TARGET_API_URL"
            value = "https://openrouter.ai/api/v1"
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 8787
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/livez"
              port = 8787
            }
            initial_delay_seconds = 10
            period_seconds        = 20
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "headroom" {
  metadata {
    name      = "headroom"
    namespace = "default"
  }
  spec {
    selector = {
      app = "headroom"
    }
    port {
      port        = 8787
      target_port = 8787
    }
  }
}

resource "kubernetes_ingress_v1" "headroom" {
  metadata {
    name      = "headroom"
    namespace = "default"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "headroom.kms-lab.in.ua"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "headroom"
              port {
                number = 8787
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service.headroom
  ]
}
