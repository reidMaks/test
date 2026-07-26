data "bitwarden-secrets_secret" "wg_hub_server" {
  id = "f307737a-9587-40b8-b39b-b493009b0043"
}

resource "kubernetes_namespace" "wg_hub" {
  metadata {
    name = "wg-hub"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "kubernetes_secret" "wg_hub_config" {
  metadata {
    name      = "wg-hub-config"
    namespace = kubernetes_namespace.wg_hub.metadata[0].name
  }
  data = {
    "wg0.conf" = data.bitwarden-secrets_secret.wg_hub_server.value
  }
}

resource "kubernetes_deployment" "wg_hub" {
  metadata {
    name      = "wg-hub"
    namespace = kubernetes_namespace.wg_hub.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "wg-hub"
      }
    }

    template {
      metadata {
        labels = {
          app = "wg-hub"
        }
      }

      spec {
        # ПРИЦВЯХОВУЄМО ПОД ДО OCI-НОДИ
        node_selector = {
          "kubernetes.io/hostname" = "talos-cp-oci"
        }

        container {
          name  = "wg-server"
          image = "alpine:3.19"

          security_context {
            privileged = true
            capabilities {
              add = ["NET_ADMIN"]
            }
          }

          # Прокидаємо порт напряму на інтерфейс Oracle Cloud
          port {
            container_port = 51821
            host_port      = 51821
            protocol       = "UDP"
          }

          command = ["/bin/sh", "-c"]
          args = [
            <<-EOF
            apk add --no-cache wireguard-tools iptables socat dnsmasq

            mkdir -p /etc/wireguard
            cp /etc/wireguard-secret/wg0.conf /etc/wireguard/wg0.conf
            chmod 600 /etc/wireguard/wg0.conf

            wg-quick up wg0
            echo "WireGuard Hub is UP!"

            # Налаштування внутрішнього DNS для клієнтів (iPhone тощо)
            cat << 'DNS' > /etc/dnsmasq.conf
            server=1.1.1.1
            server=1.0.0.1
            address=/.kms-lab.in.ua/10.9.0.1
            bind-interfaces
            listen-address=10.9.0.1
            DNS
            dnsmasq &

            # Проксі для Kubernetes-сервісів (paperless, longhorn тощо)
            socat TCP4-LISTEN:80,fork,reuseaddr TCP4:traefik.traefik-system.svc.cluster.local:80 &
            socat TCP4-LISTEN:443,fork,reuseaddr TCP4:traefik.traefik-system.svc.cluster.local:443 &

            wait
            EOF
          ]

          volume_mount {
            name       = "wg-secret"
            mount_path = "/etc/wireguard-secret"
            read_only  = true
          }
        }

        volume {
          name = "wg-secret"
          secret {
            secret_name = kubernetes_secret.wg_hub_config.metadata[0].name
          }
        }
      }
    }
  }
}
