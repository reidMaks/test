# ==========================================
# In-Cluster Prometheus MCP Server
# ==========================================

# 1. Deployment
resource "kubernetes_deployment" "prom_mcp" {
  metadata {
    name      = "prometheus-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app                         = "prometheus-mcp"
      stack                       = "ai"
      "app.kubernetes.io/part-of" = "ai-stack"
    }
    annotations = {
      "kubernetes.io/description" = "AI Stack: In-cluster remote Prometheus/VictoriaMetrics MCP server for Antigravity & Claude Code (ADR-032)"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "prometheus-mcp"
      }
    }

    template {
      metadata {
        labels = {
          app                         = "prometheus-mcp"
          stack                       = "ai"
          "app.kubernetes.io/part-of" = "ai-stack"
        }
      }

      spec {
        automount_service_account_token = false

        container {
          name = "prometheus-mcp-server"
          # Версія v1.6.2 (має ендпоінт /health). Зафіксовано за sha256-дайджестом,
          # оскільки автор репозиторію припинив пушити семвер-теги в GHCR після 1.4.2
          # і публікує нові релізи лише під тегом :latest.
          image = "ghcr.io/pab1it0/prometheus-mcp-server:latest@sha256:3c3921301229618d0b00a46a06e3b0c25745b31855f16919cf7b4fa040d47ec6"

          env {
            name  = "PROMETHEUS_URL"
            value = var.prometheus_url
          }

          env {
            name  = "PROMETHEUS_MCP_SERVER_TRANSPORT"
            value = "http"
          }

          env {
            name  = "PROMETHEUS_MCP_BIND_HOST"
            value = "0.0.0.0"
          }

          env {
            name  = "PROMETHEUS_MCP_BIND_PORT"
            value = "8080"
          }

          port {
            name           = "http"
            container_port = 8080
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
}

# 2. Service
resource "kubernetes_service" "prom_mcp" {
  metadata {
    name      = "prometheus-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "prometheus-mcp"
    }
  }

  spec {
    selector = {
      app = "prometheus-mcp"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
  }
}

# 3. Ingress (Internal routing via Traefik)
resource "kubernetes_ingress_v1" "prom_mcp" {
  metadata {
    name      = "prometheus-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "prometheus-mcp"
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = var.prom_mcp_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.prom_mcp.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}
