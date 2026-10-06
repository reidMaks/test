# ==========================================
# In-Cluster Kubernetes MCP Server
# ==========================================

# 1. Service Account
resource "kubernetes_service_account" "k8s_mcp" {
  metadata {
    name      = "kubernetes-mcp-sa"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "kubernetes-mcp"
    }
  }
}

# 2. Read-Only ClusterRole (Strictly no Secrets access)
resource "kubernetes_cluster_role" "k8s_mcp_read_only" {
  metadata {
    name = "k8s-mcp-read-only"
    labels = {
      app = "kubernetes-mcp"
    }
  }

  rule {
    api_groups = [
      "",
      "apps",
      "batch",
      "extensions",
      "networking.k8s.io",
      "storage.k8s.io",
      "rbac.authorization.k8s.io",
      "apiextensions.k8s.io",
      "monitoring.coreos.com",
      "traefik.io"
    ]
    resources = [
      "pods",
      "pods/log",
      "pods/status",
      "services",
      "endpoints",
      "persistentvolumeclaims",
      "configmaps",
      "namespaces",
      "nodes",
      "events",
      "limitranges",
      "resourcequotas",
      "deployments",
      "statefulsets",
      "daemonsets",
      "replicasets",
      "jobs",
      "cronjobs",
      "ingresses",
      "ingressclasses",
      "networkpolicies",
      "storageclasses",
      "persistentvolumes",
      "customresourcedefinitions"
    ]
    verbs = ["get", "list", "watch"]
  }
}

# 3. ClusterRole Binding
resource "kubernetes_cluster_role_binding" "k8s_mcp_read_only" {
  metadata {
    name = "k8s-mcp-read-only-binding"
    labels = {
      app = "kubernetes-mcp"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.k8s_mcp_read_only.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.k8s_mcp.metadata[0].name
    namespace = kubernetes_namespace.mcp.metadata[0].name
  }
}

# 4. ConfigMap with Server Configuration
resource "kubernetes_config_map" "k8s_mcp_config" {
  metadata {
    name      = "kubernetes-mcp-config"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "kubernetes-mcp"
    }
  }

  data = {
    "config.toml" = <<-EOT
      port = "8080"
      bind_address = "0.0.0.0"
      metrics_port = "8081"
      stateless = true
      disable_localhost_protection = true
      read_only = true
      log_level = 0
      list_output = "table"

      # Explicit defense-in-depth: Deny access to sensitive resources
      [[denied_resources]]
      group = ""
      version = "v1"
      kind = "Secret"
    EOT
  }
}

# 5. Deployment
resource "kubernetes_deployment" "k8s_mcp" {
  metadata {
    name      = "kubernetes-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "kubernetes-mcp"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "kubernetes-mcp"
      }
    }

    template {
      metadata {
        labels = {
          app = "kubernetes-mcp"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.k8s_mcp.metadata[0].name

        container {
          name  = "kubernetes-mcp-server"
          image = "ghcr.io/containers/kubernetes-mcp-server:latest"
          args  = ["--config", "/etc/kubernetes-mcp-server/config.toml"]

          port {
            name           = "mcp"
            container_port = 8080
          }

          port {
            name           = "metrics"
            container_port = 8081
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
              path = "/healthz"
              port = 8081
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8081
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/kubernetes-mcp-server"
            read_only  = true
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.k8s_mcp_config.metadata[0].name
          }
        }
      }
    }
  }
}

# 6. Service
resource "kubernetes_service" "k8s_mcp" {
  metadata {
    name      = "kubernetes-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "kubernetes-mcp"
    }
  }

  spec {
    selector = {
      app = "kubernetes-mcp"
    }

    port {
      name        = "mcp"
      port        = 8080
      target_port = 8080
    }

    port {
      name        = "metrics"
      port        = 8081
      target_port = 8081
    }
  }
}

# 7. Ingress (Internal routing via Traefik)
resource "kubernetes_ingress_v1" "k8s_mcp" {
  metadata {
    name      = "kubernetes-mcp"
    namespace = kubernetes_namespace.mcp.metadata[0].name
    labels = {
      app = "kubernetes-mcp"
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = var.k8s_mcp_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.k8s_mcp.metadata[0].name
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
