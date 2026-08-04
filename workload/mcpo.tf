# ==========================================
# MCPO (MCP-to-OpenAPI proxy for Open WebUI)
# ==========================================

data "bitwarden-secrets_secret" "github_token" {
  id = "babc4c2e-657a-4658-b105-b49c0138efa1"
}

resource "kubernetes_secret" "mcpo_github_token" {
  metadata {
    name      = "mcpo-github-token"
    namespace = "default"
  }

  data = {
    GITHUB_PERSONAL_ACCESS_TOKEN = data.bitwarden-secrets_secret.github_token.value
  }
}

# Service Account for MCPO (useful for when we add Kubernetes MCP)
resource "kubernetes_service_account" "mcpo" {
  metadata {
    name      = "mcpo-sa"
    namespace = "default"
  }
}

# Read-only ClusterRole for Kubernetes MCP testing
resource "kubernetes_cluster_role" "mcpo_read_only" {
  metadata {
    name = "mcpo-read-only"
  }

  rule {
    api_groups = ["", "apps", "batch", "extensions", "networking.k8s.io", "rbac.authorization.k8s.io"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "mcpo_read_only_binding" {
  metadata {
    name = "mcpo-read-only-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.mcpo_read_only.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.mcpo.metadata[0].name
    namespace = kubernetes_service_account.mcpo.metadata[0].namespace
  }
}

# ConfigMap with MCPO configuration
resource "kubernetes_config_map" "mcpo_config" {
  metadata {
    name      = "mcpo-config"
    namespace = "default"
  }

  data = {
    "config.json" = jsonencode({
      "mcpServers" = {
        "kubernetes" = {
          "command" = "npx"
          "args"    = ["-y", "mcp-server-kubernetes"]
        }
        "prometheus" = {
          "command" = "npx"
          "args"    = ["-y", "prometheus-mcp-server"]
          "env" = {
            "PROMETHEUS_URL" = "http://vmsingle-vm-victoria-metrics-k8s-stack.monitoring.svc.cluster.local:8428"
          }
        }
        "github" = {
          "command" = "npx"
          "args"    = ["-y", "@modelcontextprotocol/server-github"]
        }
      }
    })
  }
}

# Deployment
resource "kubernetes_deployment" "mcpo" {
  metadata {
    name      = "mcpo"
    namespace = "default"
    labels = {
      app = "mcpo"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "mcpo"
      }
    }
    template {
      metadata {
        labels = {
          app = "mcpo"
        }
      }
      spec {
        service_account_name = kubernetes_service_account.mcpo.metadata[0].name

        container {
          name  = "mcpo"
          image = "ghcr.io/open-webui/mcpo:main"

          # Command to start MCPO (with kubectl installation)
          command = ["/bin/sh", "-c"]
          args = [
            "curl -sLO https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl && chmod +x kubectl && mv kubectl /usr/local/bin/ && mcpo --config /app/config/config.json --host 0.0.0.0 --port 8000"
          ]

          port {
            container_port = 8000
          }

          env {
            name = "GITHUB_PERSONAL_ACCESS_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mcpo_github_token.metadata[0].name
                key  = "GITHUB_PERSONAL_ACCESS_TOKEN"
              }
            }
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/app/config"
          }
        }

        volume {
          name = "config-volume"
          config_map {
            name = kubernetes_config_map.mcpo_config.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "mcpo" {
  metadata {
    name      = "mcpo-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "mcpo"
    }

    port {
      port        = 8000
      target_port = 8000
    }
  }
}

# Ingress for MCPO (Internal network only)
resource "kubernetes_ingress_v1" "mcpo" {
  metadata {
    name      = "mcpo"
    namespace = "default"
  }
  spec {
    ingress_class_name = "traefik"
    rule {
      host = "mcpo.kms-lab.in.ua"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.mcpo.metadata[0].name
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
