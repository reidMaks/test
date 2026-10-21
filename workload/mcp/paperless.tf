# ==========================================
# In-Cluster Paperless-ngx MCP Server
# ==========================================

# 1. ServiceAccount & Scoped RBAC (for manage.py drf_create_token via kubectl exec)
resource "kubernetes_service_account" "paperless_mcp" {
  metadata {
    name      = "paperless-mcp-sa"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "paperless-mcp"
    }
  }
}

resource "kubernetes_role" "paperless_mcp_exec" {
  metadata {
    name      = "paperless-mcp-exec"
    namespace = "default"
    labels = {
      app = "paperless-mcp"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create", "get"]
  }
}

resource "kubernetes_role_binding" "paperless_mcp_exec" {
  metadata {
    name      = "paperless-mcp-exec-binding"
    namespace = "default"
    labels = {
      app = "paperless-mcp"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.paperless_mcp_exec.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.paperless_mcp.metadata[0].name
    namespace = kubernetes_namespace.mcp.metadata[0].name
  }
}

# 2. Deployment
resource "kubernetes_deployment" "paperless_mcp" {
  metadata {
    name      = "paperless-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app                         = "paperless-mcp"
      stack                       = "ai"
      "app.kubernetes.io/part-of" = "ai-stack"
    }
    annotations = {
      "kubernetes.io/description" = "AI Stack: In-cluster remote Paperless-ngx MCP server for Antigravity & Claude Code (ADR-032)"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "paperless-mcp"
      }
    }

    template {
      metadata {
        labels = {
          app                         = "paperless-mcp"
          stack                       = "ai"
          "app.kubernetes.io/part-of" = "ai-stack"
        }
      }

      spec {
        service_account_name            = kubernetes_service_account.paperless_mcp.metadata[0].name
        automount_service_account_token = true
        node_selector = {
          "topology.kubernetes.io/zone" = "home"
        }

        volume {
          name = "token-vol"
          empty_dir {
            medium = "Memory"
          }
        }

        # Retrieves (or creates if missing) the DRF API token directly inside the
        # running Paperless container using its native Django management command.
        init_container {
          name  = "resolve-api-token"
          image = "alpine/k8s:1.36.1"

          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
            set -eu
            POD=$(kubectl get pod -n default -l app.kubernetes.io/instance=paperless --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
            kubectl exec -n default "$POD" -- python3 manage.py drf_create_token admin | awk '/Generated token/ {print $3}' > /run/paperless-mcp/token
            chmod 0444 /run/paperless-mcp/token
            test -s /run/paperless-mcp/token
            EOT
          ]

          volume_mount {
            name       = "token-vol"
            mount_path = "/run/paperless-mcp"
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }
        }

        container {
          name  = "paperless-mcp-server"
          image = "ghcr.io/cubinet-code/paperless-ngx-mcp:3.2.1"

          command = ["/bin/sh", "-c"]
          args = [
            "read -r PAPERLESS_API_KEY < /run/paperless-mcp/token && export PAPERLESS_API_KEY && exec node build/index.js --http --port 3000"
          ]

          env {
            name  = "PAPERLESS_URL"
            value = var.paperless_internal_url
          }

          env {
            name  = "PAPERLESS_PUBLIC_URL"
            value = var.paperless_public_url
          }

          port {
            name           = "http"
            container_port = 3000
          }

          volume_mount {
            name       = "token-vol"
            mount_path = "/run/paperless-mcp"
            read_only  = true
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
              port = 3000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            tcp_socket {
              port = 3000
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_role_binding.paperless_mcp_exec
  ]
}

# 3. Service
resource "kubernetes_service" "paperless_mcp" {
  metadata {
    name      = "paperless-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "paperless-mcp"
    }
  }

  spec {
    selector = {
      app = "paperless-mcp"
    }

    port {
      name        = "http"
      port        = 3000
      target_port = 3000
    }
  }
}

# 4. Ingress (Internal routing via Traefik)
resource "kubernetes_ingress_v1" "paperless_mcp" {
  metadata {
    name      = "paperless-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "paperless-mcp"
    }
    annotations = {
      "gatus.home-operations.com/endpoint" = yamlencode({
        group      = "MCP Servers"
        path       = "/mcp"
        conditions = ["[STATUS] == 400"]
      })
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = var.paperless_mcp_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.paperless_mcp.metadata[0].name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }
  }
}
