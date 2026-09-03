# ==========================================
# MOSQUITTO (крайовий брокер для датчика HTRAM)
# ==========================================
# Це НЕ заміна аддону Mosquitto. Аддон лишається брокером Home Assistant і
# zigbee2mqtt: Supervisor сам видає їм облікові дані, і чіпати це немає
# причини. Тутешній брокер обслуговує рівно один пристрій.
#
# Чому датчик не пускає аддон. Він надсилає логін виду
# "1617:V1.00 :<випадкове число>", а паролем -- sha256 від цього ж рядка.
# Логін новий на кожне підключення, тож password_file його не перевірить, а
# allow_anonymous не рятує: анонімний режим діє лише на клієнтів, які логіна
# не надсилають узагалі. Аддон же вантажить auth_plugin вище за include_dir
# своєї customize-теки, тому per_listener_settings звідти вже "пізно" --
# брокер відмовляється стартувати. Перевірено на eclipse-mosquitto:2.
#
# Датчик говорить MQTT поверх WebSocket, тобто звичайним HTTP Upgrade, і
# надсилає коректний заголовок Host. Тому TLS знімає traefik, як і для решти
# сервісів, а брокер слухає простий websockets усередині кластера -- ані
# власної адреси metallb, ані власного сертифіката не треба.
#
# Містка тут немає навмисно. Його конфігуруємо пізніше з боку аддона, у його
# customize-теці: аддон сам ходить сюди по теми. Так у цьому конфігу не
# лишається жодного пароля -- вихідне з'єднання йде на анонімний лістенер.

resource "kubernetes_config_map" "mosquitto" {
  metadata {
    name      = "mosquitto-config"
    namespace = "default"
  }

  data = {
    "mosquitto.conf" = <<-EOT
      log_dest stdout
      log_type error
      log_type warning
      log_type notice
      log_timestamp_format %Y-%m-%d %H:%M:%S

      persistence true
      persistence_location /mosquitto/data/

      # per_listener_settings тут не потрібен: обидва лістенери мають однакові
      # налаштування безпеки, тож глобальні і є їхніми. У mosquitto 2.1 ця
      # опція вже позначена застарілою і тягне за собою два попередження.
      allow_anonymous true
      acl_file /mosquitto/config/acl

      # Датчики. TLS знімає traefik, сюди приходить розшифрований websocket.
      listener 8080
      protocol websockets

      # Місток з аддона. Окремий лістенер потрібен тому, що місток mosquitto
      # уміє лише простий MQTT -- у websockets-лістенер він шле сирий CONNECT
      # і дістає "bad socket read/write". Перевірено на eclipse-mosquitto:2.
      listener 1883
      protocol mqtt
    EOT

    # pattern, а не topic: рядки topic до першої директиви user діють лише на
    # клієнтів без логіна, а датчик логін надсилає -- і під них не підпадає.
    # З topic брокер мовчки ріже телеметрію. %c підставляє client id, який у
    # цього пристрою дорівнює серійному номеру, тож кожен датчик замкнений на
    # власні дві теми.
    #
    # Секція ha-bridge -- для майбутнього містка з боку аддона: пароля він не
    # потребує, лише впізнаваного імені, щоб дістати підписку на всі C/#.
    "acl" = <<-EOT
      pattern readwrite C/%c
      pattern readwrite D/%c

      user ha-bridge
      topic readwrite C/#
      topic readwrite D/#
    EOT
  }
}

resource "kubernetes_persistent_volume_claim" "mosquitto_data" {
  metadata {
    name      = "mosquitto-data"
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

resource "kubernetes_deployment" "mosquitto" {
  metadata {
    name      = "mosquitto"
    namespace = "default"
    labels = {
      app = "mosquitto"
    }
  }

  spec {
    replicas = 1

    # Брокер тримає стан на RWO-томі: два поди одночасно його не поділять.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "mosquitto"
      }
    }

    template {
      metadata {
        labels = {
          app = "mosquitto"
        }
        annotations = {
          # Под має перезапуститись, коли змінився конфіг або ACL.
          "checksum/config" = sha256(join("", values(kubernetes_config_map.mosquitto.data)))
        }
      }

      spec {
        # Увесь трафік сюди приходить із домашньої мережі; под на ноді OCI
        # тягнув би його через wg-hub.
        node_selector = {
          "topology.kubernetes.io/zone" = "home"
        }

        # mosquitto читає mosquitto.conf ще як root, а потім скидає привілеї
        # до користувача mosquitto -- і вже після цього відкриває acl_file.
        # Змонтований ConfigMap лишається root:root, тож ACL стає нечитним і
        # брокер падає з "Unable to open acl_file". fsGroup на цей монтаж не
        # подіяв, тому розкладаємо файли initContainer'ом: копія в emptyDir із
        # правильним власником не залежить від поведінки kubelet.
        init_container {
          name  = "prepare-config"
          image = "eclipse-mosquitto:2"

          security_context {
            run_as_user = 0
          }

          command = [
            "sh", "-c",
            "cp /config-src/* /mosquitto/config/ && chown mosquitto:mosquitto /mosquitto/config/* && chmod 0600 /mosquitto/config/*",
          ]

          volume_mount {
            name       = "config-src"
            mount_path = "/config-src"
          }
          volume_mount {
            name       = "config"
            mount_path = "/mosquitto/config"
          }
        }

        container {
          name  = "mosquitto"
          image = "eclipse-mosquitto:2"

          port {
            name           = "ws"
            container_port = 8080
            protocol       = "TCP"
          }
          port {
            name           = "mqtt"
            container_port = 1883
            protocol       = "TCP"
          }

          volume_mount {
            name       = "config"
            mount_path = "/mosquitto/config"
          }
          volume_mount {
            name       = "data"
            mount_path = "/mosquitto/data"
          }

          readiness_probe {
            tcp_socket {
              port = 8080
            }
            period_seconds = 10
          }

          liveness_probe {
            tcp_socket {
              port = 8080
            }
            period_seconds = 20
          }

          resources {
            requests = {
              cpu    = "20m"
              memory = "32Mi"
            }
            limits = {
              memory = "128Mi"
            }
          }
        }

        volume {
          name = "config-src"
          config_map {
            name = kubernetes_config_map.mosquitto.metadata[0].name
          }
        }

        volume {
          name = "config"
          empty_dir {}
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.mosquitto_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "mosquitto" {
  metadata {
    name      = "mosquitto"
    namespace = "default"
  }
  spec {
    selector = {
      app = "mosquitto"
    }
    port {
      name        = "ws"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }
  }
}

# Окрема адреса в LAN для містка: аддон Mosquitto живе поза кластером, а
# ClusterIP звідти не видно. Через traefik це не пустиш -- він розбирає HTTP,
# а тут сирий MQTT.
resource "kubernetes_service" "mosquitto_mqtt" {
  metadata {
    name      = "mosquitto-mqtt"
    namespace = "default"
    annotations = {
      # Пул metallb 192.168.0.45-49. Зайнято: .45 traefik, .46 speedtest
      # (бере адресу динамічно, без анотації -- у коді її не видно, лише
      # через kubectl get svc -A), .47 piper. Вільні: .48 і .49.
      "metallb.universe.tf/loadBalancerIPs" = "192.168.0.48"
    }
  }
  spec {
    type = "LoadBalancer"
    selector = {
      app = "mosquitto"
    }
    port {
      name        = "mqtt"
      port        = 1883
      target_port = 1883
      protocol    = "TCP"
    }
  }
}

# Датчик ходить на https://<host>/ і апгрейдиться до websocket -- traefik
# проксує це без окремих налаштувань. Сертифікат бере усталений TLSStore
# (*.kms-lab.in.ua), а датчик його однаково не перевіряє.
#
# Назовні це не виходить: у зоні kms-lab.in.ua публічно тунелюються лише
# іменовані CNAME, а wildcard-запис веде на 10.9.0.1 (wg-hub).
resource "kubernetes_ingress_v1" "mosquitto" {
  metadata {
    name      = "mosquitto"
    namespace = "default"
    annotations = {
      # Лістенер websockets відповідає на звичайний GET розривом з'єднання, і
      # traefik віддає 502 -- gatus інакше вважав би сервіс мертвим. Саме 502
      # (а не 503) означає, що бекенд доступний і сам закрив з'єднання, тож
      # як ознака життя воно годиться.
      "gatus.io/status" = "[STATUS] == 502"
    }
  }
  spec {
    ingress_class_name = "traefik"
    rule {
      host = "mqtt.kms-lab.in.ua"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.mosquitto.metadata[0].name
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
