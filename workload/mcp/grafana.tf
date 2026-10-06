# ==========================================
# In-Cluster Grafana MCP Server
# ==========================================

# 1. Service Account in Grafana (Declarative via Grafana Provider)
resource "grafana_service_account" "mcp_viewer" {
  name        = "mcp-viewer"
  role        = "Viewer"
  is_disabled = false
}

# 2. Service Account Token
resource "grafana_service_account_token" "mcp_token" {
  name               = "mcp-viewer-token"
  service_account_id = grafana_service_account.mcp_viewer.id
}

# 3. Store Token in Kubernetes Secret
resource "kubernetes_secret" "grafana_mcp_token" {
  metadata {
    name      = "grafana-mcp-token"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "grafana-mcp"
    }
  }

  data = {
    GRAFANA_SERVICE_ACCOUNT_TOKEN = grafana_service_account_token.mcp_token.key
  }
}

# 4. Deployment
resource "kubernetes_deployment" "grafana_mcp" {
  metadata {
    name      = "grafana-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "grafana-mcp"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "grafana-mcp"
      }
    }

    template {
      metadata {
        labels = {
          app = "grafana-mcp"
        }
      }

      spec {
        automount_service_account_token = false

        container {
          name  = "grafana-mcp-server"
          image = "docker.io/grafana/mcp-grafana:latest"
          args = [
            "-t", "streamable-http",
            "-allowed-hosts", "*",
            "-allowed-origins", "*",
          ]

          env {
            name  = "GRAFANA_URL"
            value = var.grafana_internal_url
          }

          env {
            name = "GRAFANA_SERVICE_ACCOUNT_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.grafana_mcp_token.metadata[0].name
                key  = "GRAFANA_SERVICE_ACCOUNT_TOKEN"
              }
            }
          }

          port {
            name           = "http"
            container_port = 8000
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
            tcp_socket {
              port = 8000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            tcp_socket {
              port = 8000
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }
        }
      }
    }
  }
}

# 5. Service
resource "kubernetes_service" "grafana_mcp" {
  metadata {
    name      = "grafana-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "grafana-mcp"
    }
  }

  spec {
    selector = {
      app = "grafana-mcp"
    }

    port {
      name        = "http"
      port        = 8000
      target_port = 8000
    }
  }
}

# 6. Ingress (Internal routing via Traefik)
resource "kubernetes_ingress_v1" "grafana_mcp" {
  metadata {
    name      = "grafana-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "grafana-mcp"
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = var.grafana_mcp_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.grafana_mcp.metadata[0].name
              port {
                number = 8000
              }
            }
          }
        }
      }
    }
  }
}
