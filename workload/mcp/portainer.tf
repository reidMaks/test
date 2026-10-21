# ==========================================
# In-Cluster Portainer MCP Server
# ==========================================

# 1. Store Gate Token in Kubernetes Secret
resource "kubernetes_secret" "portainer_mcp_token" {
  metadata {
    name      = "portainer-mcp-token"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "portainer-mcp"
    }
  }

  data = {
    PORTAINER_MCP_AUTH_TOKEN = var.portainer_mcp_gate_token
  }
}

# 2. Deployment
resource "kubernetes_deployment" "portainer_mcp" {
  metadata {
    name      = "portainer-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app                         = "portainer-mcp"
      stack                       = "ai"
      "app.kubernetes.io/part-of" = "ai-stack"
    }
    annotations = {
      "kubernetes.io/description" = "AI Stack: In-cluster remote Portainer MCP server for Antigravity & Claude Code (ADR-032)"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "portainer-mcp"
      }
    }

    template {
      metadata {
        labels = {
          app                         = "portainer-mcp"
          stack                       = "ai"
          "app.kubernetes.io/part-of" = "ai-stack"
        }
      }

      spec {
        automount_service_account_token = false
        node_selector = {
          "topology.kubernetes.io/zone" = "home"
        }

        container {
          name  = "portainer-mcp-server"
          image = "docker.io/portainer/portainer-mcp:2.45.1"

          env {
            name  = "PORTAINER_URL"
            value = var.portainer_url
          }

          env {
            name  = "PORTAINER_TLS_VERIFY"
            value = "0"
          }

          env {
            name  = "PORTAINER_MCP_HTTP_PORT"
            value = "17717"
          }

          env {
            name  = "PORTAINER_MCP_ALLOWED_HOSTS"
            value = "${var.portainer_mcp_host},${var.portainer_mcp_host}:*,127.0.0.1:*,localhost:*"
          }

          env {
            name  = "PORTAINER_MCP_DANGEROUSLY_ALLOW_PLAINTEXT_HTTP"
            value = "1"
          }

          env {
            name  = "PORTAINER_PROFILES"
            value = "BASE,DOCKER,ADMIN"
          }

          env {
            name  = "PORTAINER_TAGS_EXTRA"
            value = "observability,webhooks"
          }

          env {
            name  = "PORTAINER_MCP_DISABLE_GUIDANCE_GATE"
            value = "1"
          }

          env {
            name = "PORTAINER_MCP_AUTH_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.portainer_mcp_token.metadata[0].name
                key  = "PORTAINER_MCP_AUTH_TOKEN"
              }
            }
          }

          port {
            name           = "http"
            container_port = 17717
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            tcp_socket {
              port = 17717
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            tcp_socket {
              port = 17717
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }
        }
      }
    }
  }
}

# 3. Service
resource "kubernetes_service" "portainer_mcp" {
  metadata {
    name      = "portainer-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "portainer-mcp"
    }
  }

  spec {
    selector = {
      app = "portainer-mcp"
    }

    port {
      name        = "http"
      port        = 17717
      target_port = 17717
    }
  }
}

# 4. Traefik Middleware: In-Cluster Zero-Client-Secret Header Injection
resource "kubernetes_manifest" "portainer_mcp_auth_middleware" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "portainer-mcp-auth"
      namespace = kubernetes_namespace.mcp.metadata[0].name
      labels = {
        app = "portainer-mcp"
      }
    }
    spec = {
      headers = {
        customRequestHeaders = {
          Authorization       = "Bearer ${var.portainer_mcp_gate_token}"
          X-Portainer-API-Key = var.portainer_api_key
        }
      }
    }
  }
}

# 5. Ingress (Internal routing via Traefik)
resource "kubernetes_ingress_v1" "portainer_mcp" {
  metadata {
    name      = "portainer-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "portainer-mcp"
    }
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "${kubernetes_namespace.mcp.metadata[0].name}-portainer-mcp-auth@kubernetescrd"
      "gatus.home-operations.com/endpoint" = yamlencode({
        group      = "MCP Servers"
        path       = "/mcp"
        conditions = ["[STATUS] == any(400, 406)"]
      })
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = var.portainer_mcp_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.portainer_mcp.metadata[0].name
              port {
                number = 17717
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_manifest.portainer_mcp_auth_middleware
  ]
}
