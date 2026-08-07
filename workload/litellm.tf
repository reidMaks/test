# ==========================================
# LiteLLM Proxy
# ==========================================

resource "random_password" "litellm_db_password" {
  length  = 32
  special = false
}

resource "random_password" "litellm_master_key" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "litellm_db_password_cnpg" {
  metadata {
    name      = "litellm-db-password"
    namespace = "cnpg-system"
  }
  type = "kubernetes.io/basic-auth"
  data = {
    username = "litellm"
    password = random_password.litellm_db_password.result
  }
}

resource "kubernetes_manifest" "litellm_role" {
  depends_on = [kubernetes_secret.litellm_db_password_cnpg]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "DatabaseRole"
    metadata = {
      name      = "litellm"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "litellm"
      login = true
      passwordSecret = {
        name = kubernetes_secret.litellm_db_password_cnpg.metadata[0].name
      }
    }
  }
}

resource "kubernetes_manifest" "litellm_database" {
  depends_on = [kubernetes_manifest.litellm_role]
  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"
    metadata = {
      name      = "litellm"
      namespace = "cnpg-system"
      labels = {
        "cnpg.io/cluster" = "shared-db"
      }
    }
    spec = {
      cluster = {
        name = "shared-db"
      }
      name  = "litellm"
      owner = "litellm"
    }
  }
}

resource "kubernetes_config_map" "litellm_config" {
  metadata {
    name      = "litellm-config"
    namespace = "default"
  }

  data = {
    "config.yaml" = <<-EOT
model_list: []

router_settings:
  routing_strategy: cost-based-routing
  fallback_next_model: true

general_settings:
  master_key: "os.environ/LITELLM_MASTER_KEY"
  database_url: "os.environ/DATABASE_URL"
EOT
  }
}

resource "kubernetes_deployment" "litellm" {
  metadata {
    name      = "litellm"
    namespace = "default"
    labels = {
      app = "litellm"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "litellm"
      }
    }

    template {
      metadata {
        labels = {
          app = "litellm"
        }
      }

      spec {
        container {
          name  = "litellm"
          image = "ghcr.io/berriai/litellm:main-latest"
          args  = ["--config", "/app/config.yaml"]

          port {
            container_port = 4000
          }

          env {
            name  = "LITELLM_MASTER_KEY"
            value = random_password.litellm_master_key.result
          }
          env {
            name  = "STORE_MODEL_IN_DB"
            value = "True"
          }
          env {
            name  = "DATABASE_URL"
            value = "postgresql://litellm:${random_password.litellm_db_password.result}@shared-db-rw.cnpg-system.svc.cluster.local:5432/litellm"
          }
          env {
            name  = "OPENROUTER_API_KEY"
            value = data.bitwarden-secrets_secret.open_router_api_key.value
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/app/config.yaml"
            sub_path   = "config.yaml"
          }
        }

        volume {
          name = "config-volume"
          config_map {
            name = kubernetes_config_map.litellm_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "litellm" {
  metadata {
    name      = "litellm"
    namespace = "default"
  }
  spec {
    selector = {
      app = "litellm"
    }
    port {
      port        = 4000
      target_port = 4000
    }
  }
}

resource "kubernetes_ingress_v1" "litellm_ui" {
  metadata {
    name      = "litellm-ui"
    namespace = "default"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "litellm.kms-lab.in.ua"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "litellm"
              port {
                number = 4000
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service.litellm
  ]
}

output "litellm_master_key" {
  description = "Master Key to login to LiteLLM Admin UI"
  value       = random_password.litellm_master_key.result
  sensitive   = true
}
