# ==========================================
# PIPER (Ukrainian TTS для Home Assistant)
# ==========================================
# Home Assistant Assist інтегрується з Piper через Wyoming-протокол (raw TCP,
# порт 10200) -- не HTTP, тому інгрес тут не потрібен і не підійшов би.
# Використовуємо офіційний lscr.io/linuxserver/piper (wyoming-piper під
# капотом, готовий образ під amd64/arm64, підтримує завантаження голосів
# через PIPER_VOICE без ручного встановлення пакетів).
#
# Модель: uk_UA-tetiana-high (обрано користувачем) -- найкраща якість голосу
# для української, яку підтримує piper; навіть "high" рівень легко тягне CPU
# домашніх нод (Piper проєктувався під Raspberry Pi 4).

resource "kubernetes_persistent_volume_claim" "piper_data" {
  metadata {
    name      = "piper-data"
    namespace = "default"
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "piper" {
  metadata {
    name      = "piper"
    namespace = "default"
    labels = {
      app = "piper"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "piper"
      }
    }

    template {
      metadata {
        labels = {
          app = "piper"
        }
      }

      spec {
        # Лише домашня зона: talos-b7w-rgq (control-plane, home) має NoSchedule
        # taint, тож фактично пін на talos-f9o-10o / talos-wfh-33w -- нижча
        # затримка для голосового пайплайна Home Assistant.
        node_selector = {
          "topology.kubernetes.io/zone" = "home"
        }

        container {
          name  = "piper"
          image = "lscr.io/linuxserver/piper:latest"

          env {
            name  = "PIPER_VOICE"
            value = "uk_UA-tetiana-high"
          }
          env {
            name  = "TZ"
            value = "Europe/Kyiv"
          }

          port {
            container_port = 10200
            protocol       = "TCP"
          }

          volume_mount {
            name       = "piper-data"
            mount_path = "/config"
          }

          # Wyoming -- не HTTP, тож перевіряємо просто відкритий TCP-сокет.
          startup_probe {
            tcp_socket {
              port = 10200
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            failure_threshold     = 24
          }

          readiness_probe {
            tcp_socket {
              port = 10200
            }
            period_seconds = 10
          }

          liveness_probe {
            tcp_socket {
              port = 10200
            }
            period_seconds = 20
          }

          # Той самий piper-движок, що й у HTTP-варіанті (~250Mi під час
          # синтезу) -- request під усталене навантаження, limit із запасом.
          resources {
            requests = {
              cpu    = "150m"
              memory = "192Mi"
            }
            limits = {
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "piper-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.piper_data.metadata[0].name
          }
        }
      }
    }
  }
}

# Home Assistant живе поза кластером у домашній мережі, тож для Wyoming
# (raw TCP, не HTTP -- ingress не годиться) потрібна LAN-адреса напряму
# через metallb, так само як traefik отримує 192.168.0.45.
resource "kubernetes_service" "piper" {
  metadata {
    name      = "piper"
    namespace = "default"
    annotations = {
      "metallb.universe.tf/loadBalancerIPs" = "192.168.0.47"
    }
  }
  spec {
    type = "LoadBalancer"
    selector = {
      app = "piper"
    }
    port {
      name        = "wyoming"
      port        = 10200
      target_port = 10200
      protocol    = "TCP"
    }
  }
}
