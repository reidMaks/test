# ==========================================
# [AI STACK] Headroom Proxy (LLM context compression)
# Статус: Вимкнено (replicas = 0).
# Призначення: Проксі між клієнтом (LiteLLM / Claude Code) та API (Anthropic / OpenRouter)
# для стиснення великих JSON/логів у промптах для економії токенів (див. ADR-018).
# ==========================================

resource "kubernetes_deployment" "headroom" {
  metadata {
    name      = "headroom"
    namespace = "default"
    labels = {
      app                         = "headroom"
      stack                       = "ai"
      "app.kubernetes.io/part-of" = "ai-stack"
    }
    annotations = {
      "kubernetes.io/description" = "AI Stack: Context-compression proxy for Claude Code & LiteLLM -> Anthropic/OpenRouter (ADR-018)"
    }
  }

  spec {
    # Масштабовано в 0 (разом із Open WebUI та LiteLLM)
    replicas = 0

    selector {
      match_labels = {
        app = "headroom"
      }
    }

    template {
      metadata {
        labels = {
          app                         = "headroom"
          stack                       = "ai"
          "app.kubernetes.io/part-of" = "ai-stack"
        }
      }

      spec {
        container {
          name  = "headroom"
          image = "ghcr.io/headroomlabs-ai/headroom:sha-85786b3"
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
          env {
            name  = "HEADROOM_ALLOW_UNAUTHENTICATED_BIND"
            value = "1"
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
