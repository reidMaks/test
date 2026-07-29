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

    strategy {
      type = "Recreate"
    }

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
        node_selector = {
          "kubernetes.io/hostname" = "talos-cp-oci"
        }

        # 1. WireGuard Server (Тільки піднімає інтерфейс)
        container {
          name  = "wg-server"
          image = "alpine:3.19"
          security_context {
            privileged = true
            capabilities {
              add = ["NET_ADMIN"]
            }
          }
          port {
            container_port = 51821
            host_port      = 51821
            protocol       = "UDP"
          }
          command = ["/bin/sh", "-c"]
          args = [
            <<-EOF
            set -e
            apk add --no-cache wireguard-tools iptables
            mkdir -p /etc/wireguard
            cp /etc/wireguard-secret/wg0.conf /etc/wireguard/wg0.conf
            chmod 600 /etc/wireguard/wg0.conf
            wg-quick up wg0
            echo "WireGuard Hub is UP!"
            sleep infinity
            EOF
          ]
          volume_mount {
            name       = "wg-secret"
            mount_path = "/etc/wireguard-secret"
            read_only  = true
          }
        }

        # 2. Внутрішній DNS для VPN клієнтів
        container {
          name    = "dns-server"
          image   = "alpine:3.19"
          command = ["/bin/sh", "-c"]
          args = [
            <<-EOF
            set -e
            apk add --no-cache dnsmasq
            # Чекаємо поки wg-server підніме інтерфейс
            while ! ip addr show wg0 >/dev/null 2>&1; do sleep 1; done
            cat << 'DNS' > /etc/dnsmasq.conf
            server=1.1.1.1
            server=1.0.0.1
            address=/.kms-lab.in.ua/10.9.0.1
            bind-interfaces
            listen-address=10.9.0.1
            DNS
            exec dnsmasq -k
            EOF
          ]
        }

        # 3. Вхідний проксі (Port 80)
        container {
          name  = "ingress-80"
          image = "alpine/socat:latest"
          args  = ["TCP4-LISTEN:80,fork,reuseaddr", "TCP4:traefik.traefik-system.svc.cluster.local:80"]
        }

        # 4. Вхідний проксі (Port 443)
        container {
          name  = "ingress-443"
          image = "alpine/socat:latest"
          args  = ["TCP4-LISTEN:443,fork,reuseaddr", "TCP4:traefik.traefik-system.svc.cluster.local:443"]
        }

        # 5. Вихідний проксі (Squid) для доступу в дім (Gatus)
        container {
          name    = "egress-squid"
          image   = "alpine:3.19"
          command = ["/bin/sh", "-c"]
          args = [
            <<-EOF
            set -e
            apk add --no-cache squid
            cat << 'SQUID' > /etc/squid/squid.conf
            http_port 3128
            dns_nameservers 192.168.0.1
            acl localnet src 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10
            http_access allow localnet
            http_access deny all
            SQUID
            exec squid -N
            EOF
          ]
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

resource "kubernetes_service" "wg_hub_proxy" {
  metadata {
    name      = "wg-hub-proxy"
    namespace = kubernetes_namespace.wg_hub.metadata[0].name
  }
  spec {
    selector = {
      app = "wg-hub"
    }
    port {
      name        = "squid"
      port        = 3128
      target_port = 3128
    }
  }
}
