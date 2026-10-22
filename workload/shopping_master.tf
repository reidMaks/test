# ==============================================================================
# Shopping Master — Telegram Mini App (WebApp) Ingress & Home LAN Proxy
# ==============================================================================
# Оскільки Traefik працює в зоні `oci` (Oracle Cloud), він не має прямого
# маршруту до окремих пристроїв домашньої мережі (TV-Box aml-s9xx-box 192.168.0.106),
# які не є вузлами KubeSpan. Легковаговий socat-проксі у зоні `home` приймає
# трафік від Traefik через Pod-мережу KubeSpan і передає його напряму в
# 192.168.0.106:8080 по локальній мережі.
# ==============================================================================

resource "kubernetes_deployment" "shopping_master_proxy" {
  metadata {
    name      = "shopping-master-proxy"
    namespace = "default"
    labels = {
      app = "shopping-master"
    }
    annotations = {
      "kubernetes.io/description" = "Home-zone LAN TCP forwarder to shopping-master WebApp on aml-s9xx-box (192.168.0.106:8080)"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "shopping-master"
      }
    }

    template {
      metadata {
        labels = {
          app = "shopping-master"
        }
      }

      spec {
        automount_service_account_token = false
        node_selector = {
          "topology.kubernetes.io/zone" = "home"
        }

        container {
          name  = "socat"
          image = "alpine/socat:1.8.1.3"
          args = [
            "TCP4-LISTEN:8080,fork,reuseaddr",
            "TCP4:192.168.0.106:8080"
          ]

          port {
            name           = "http"
            container_port = 8080
          }

          resources {
            requests = {
              cpu    = "5m"
              memory = "16Mi"
            }
            limits = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }

          liveness_probe {
            tcp_socket {
              port = 8080
            }
            initial_delay_seconds = 3
            period_seconds        = 15
          }

          readiness_probe {
            tcp_socket {
              port = 8080
            }
            initial_delay_seconds = 2
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "shopping_master" {
  metadata {
    name      = "shopping-master"
    namespace = "default"
    labels = {
      app = "shopping-master"
    }
  }

  spec {
    selector = {
      app = "shopping-master"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
  }
}

resource "kubernetes_ingress_v1" "shopping_master" {
  metadata {
    name      = "shopping-master"
    namespace = "default"
    labels = {
      app = "shopping-master"
    }
    annotations = {
      # Додаток використовує власну криптографічну перевірку Telegram WebApp initData
      # (HMAC-SHA256 з TELEGRAM_BOT_TOKEN + ALLOWED_TELEGRAM_IDS), тому Authentik
      # ForwardAuth тут не підключається, щоб не блокувати шторку всередині Telegram.
      "gatus.home-operations.com/endpoint" = yamlencode({
        group      = "Applications"
        path       = "/healthz"
        conditions = ["[STATUS] == 200"]
      })
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "shopping.kms-lab.in.ua"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.shopping_master.metadata[0].name
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
