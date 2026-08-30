# ==========================================
# OIKB (Open WebUI Knowledge Base Sync)
# ==========================================

locals {
  # ID бази знань з Open WebUI
  oikb_kb_id = "daafd510-c380-4431-a861-4b76f76ae160"
}

data "bitwarden-secrets_secret" "openwebui_api_key" {
  id = "b5300d2e-6b86-415a-8308-b49c013e8ebf"
}

resource "kubernetes_secret" "oikb_secrets" {
  metadata {
    name      = "oikb-secrets"
    namespace = "default"
  }

  data = {
    OPEN_WEBUI_API_KEY = data.bitwarden-secrets_secret.openwebui_api_key.value
    # Перевикористовуємо токен GitHub, який ми вже визначили в mcpo.tf
    GITHUB_TOKEN = data.bitwarden-secrets_secret.github_token.value
  }
}

resource "kubernetes_config_map" "oikb_config" {
  metadata {
    name      = "oikb-config"
    namespace = "default"
  }

  data = {
    ".oikb.yaml" = <<EOT
defaults:
  interval: 5m
  concurrency: 4

sources:
  - name: iaac-docs
    source: github:reidMaks/test
    kb-id: ${local.oikb_kb_id}
EOT
  }
}

resource "kubernetes_deployment" "oikb" {
  metadata {
    name      = "oikb"
    namespace = "default"
    labels = {
      app = "oikb"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "oikb"
      }
    }
    template {
      metadata {
        labels = {
          app = "oikb"
        }
      }
      spec {
        container {
          name    = "oikb"
          image   = "ghcr.io/open-webui/oikb:latest"
          command = ["oikb", "daemon"]

          resources {
            requests = {
              cpu    = "20m"
              memory = "128Mi"
            }
            limits = {
              memory = "256Mi"
            }
          }

          env {
            name = "OPEN_WEBUI_URL"
            # Вказуємо внутрішню DNS-адресу Open WebUI в кластері
            value = "http://open-webui.default.svc.cluster.local:80"
          }
          env {
            name = "OPEN_WEBUI_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.oikb_secrets.metadata[0].name
                key  = "OPEN_WEBUI_API_KEY"
              }
            }
          }
          env {
            name = "GITHUB_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.oikb_secrets.metadata[0].name
                key  = "GITHUB_TOKEN"
              }
            }
          }

          volume_mount {
            name       = "oikb-config-volume"
            mount_path = "/app/.oikb.yaml"
            sub_path   = ".oikb.yaml"
            read_only  = true
          }
        }

        volume {
          name = "oikb-config-volume"
          config_map {
            name = kubernetes_config_map.oikb_config.metadata[0].name
          }
        }
      }
    }
  }
}
