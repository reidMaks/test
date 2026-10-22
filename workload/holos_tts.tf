# ==========================================
# HOLOS-TTS (Ukrainian TTS для Home Assistant та AI Stack)
# ==========================================
# Замінює попередній wyoming-piper (uk_UA-tetiana-high) на ha-holos-tts
# (https://github.com/ALERTua/ha-holos-tts), який запускає модель HolosTTS
# (від patriotyk) у парі з 3-ступеневим пайплайном підготовки українського тексту:
#   1. Нейромережевий вербалізатор (m2m100-ukr-verbalization на CTranslate2) --
#      перетворює числа, час, дати, від'ємні температури та одиниці виміру у слова
#      (напр. "о 15:30, -3°C" -> "о пʼятнадцятій тридцять, мінус три градуси Цельсія").
#   2. Модель наголосів (stanza POS + словник НАНУ + ukrainian-accentor).
#   3. Фонемізатор (ipa-uk) + синтез мовлення в ONNX Runtime (int8 на CPU).
#
# Сервер одночасно надає два інтерфейси на LAN-адресі MetalLB 192.168.0.47:
#   - Wyoming-протокол (raw TCP :10200) -- пряма інтеграція з Home Assistant Assist.
#   - OpenAI-сумісний TTS API (HTTP :8000, /v1/audio/speech, /v1/audio/voices,
#     /v1/warmup, /health) -- для Open WebUI, LiteLLM та Music Assistant.

moved {
  from = kubernetes_persistent_volume_claim.piper_data
  to   = kubernetes_persistent_volume_claim.holos_tts_data
}

moved {
  from = kubernetes_deployment.piper
  to   = kubernetes_deployment.holos_tts
}

moved {
  from = kubernetes_service.piper
  to   = kubernetes_service.holos_tts
}

resource "kubernetes_persistent_volume_claim" "holos_tts_data" {
  metadata {
    name      = "holos-tts-data"
    namespace = "default"
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        # Завантажені моделі Hugging Face + Stanza займають ~2.5 ГБ,
        # плюс ~880 МБ оптимізований кеш (ONNX граф + int8 вербалізатор + вектори наголосів),
        # разом ~3.4 ГБ. Виділяємо 5Gi із запасом.
        storage = "5Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "holos_tts" {
  metadata {
    name      = "holos-tts"
    namespace = "default"
    labels = {
      app                         = "holos-tts"
      stack                       = "ai"
      "app.kubernetes.io/part-of" = "ai-stack"
    }
    annotations = {
      "kubernetes.io/description" = "AI Stack: Ukrainian HolosTTS speech server (Wyoming TCP:10200 & OpenAI HTTP:8000) for Home Assistant"
    }
  }

  spec {
    replicas = 1

    # ReadWriteOnce Longhorn PVC + ~1.4Gi-2Gi RAM моделі: спочатку зупиняємо
    # старий под перед стартом нового, щоб уникнути Multi-Attach та подвійного піку RAM.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "holos-tts"
      }
    }

    template {
      metadata {
        labels = {
          app                         = "holos-tts"
          stack                       = "ai"
          "app.kubernetes.io/part-of" = "ai-stack"
        }
      }

      spec {
        # Лише домашня зона: talos-b7w-rgq (control-plane, home) має NoSchedule
        # taint, тож фактично пін на talos-f9o-10o / talos-wfh-33w -- нижча
        # затримка для голосового пайплайна Home Assistant та локальні репліки Longhorn.
        node_selector = {
          "topology.kubernetes.io/zone" = "home"
        }

        # Контейнер працює від непривілейованого користувача appuser (1000:1000).
        # fs_group = 1000 гарантує, що kubelet надасть права запису на корінь
        # примонтованого Longhorn-тому /data для завантаження моделей та побудови кешу.
        security_context {
          run_as_user  = 1000
          run_as_group = 1000
          fs_group     = 1000
        }

        container {
          name  = "holos-tts"
          image = "ghcr.io/alertua/ha-holos-tts:1.1.0"

          env {
            name  = "TZ"
            value = "Europe/Kyiv"
          }
          env {
            name  = "HTTP_PORT"
            value = "8000"
          }
          env {
            name  = "WYOMING_PORT"
            value = "10200"
          }
          # Базовий голос за замовчуванням (у Home Assistant можна обрати будь-який
          # із 27 голосів, напр. "Гаська Шиян", "Speaker_67" тощо).
          env {
            name  = "DEFAULT_VOICE"
            value = "Speaker_67"
          }
          env {
            name  = "DEFAULT_SPEED"
            value = "1.0"
          }
          # 1: перетворювати числа, дати, час, °C та % у слова перед синтезом.
          env {
            name  = "VERBALIZE"
            value = "1"
          }
          # 0: не завантажувати Gradio Web UI (економить ~80 МБ RAM та ~5-8% фонового CPU).
          # За потреби протестувати голоси у браузері на http://192.168.0.47:8000/web/ -- змінити на "1".
          env {
            name  = "WEB_UI"
            value = "0"
          }
          # Завантажувати моделі у фоні одразу після старту контейнера.
          env {
            name  = "PRELOAD"
            value = "1"
          }
          # Обмежуємо кількість потоків ONNX Runtime / CTranslate2 на домашніх вузлах (4-6 vCPU).
          env {
            name  = "THREADS"
            value = "4"
          }
          # Оптимізація алокатора glibc (ADR-035) для своєчасного повернення пам'яті ONNX/CTranslate2.
          env {
            name  = "MALLOC_TRIM_THRESHOLD_"
            value = "65536"
          }
          env {
            name  = "MALLOC_ARENA_MAX"
            value = "2"
          }

          port {
            name           = "wyoming"
            container_port = 10200
            protocol       = "TCP"
          }

          port {
            name           = "http"
            container_port = 8000
            protocol       = "TCP"
          }

          volume_mount {
            name       = "holos-tts-data"
            mount_path = "/data"
          }

          startup_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            timeout_seconds       = 5
            failure_threshold     = 36
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            period_seconds  = 15
            timeout_seconds = 5
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            period_seconds    = 30
            timeout_seconds   = 5
            failure_threshold = 3
          }

          # Усі три моделі в пам'яті (HolosTTS int8 + Stanza + Verbalizer)
          # займають ~1.4-2.1 GiB RSS, проте під час першої побудови кешу
          # (конвертація 1.9 ГБ float32 вербалізатора в int8 + page cache cgroup v2)
          # пікове споживання перевищує 2.5 GiB. Даємо 4608Mi (4.5 GiB) ліміту.
          resources {
            requests = {
              cpu    = "150m"
              memory = "1536Mi"
            }
            limits = {
              memory = "4608Mi"
            }
          }
        }

        volume {
          name = "holos-tts-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.holos_tts_data.metadata[0].name
          }
        }
      }
    }
  }
}

# Home Assistant живе поза кластером у домашній мережі, тож відкриваємо
# LAN-адресу 192.168.0.47 напряму через MetalLB (і для Wyoming :10200,
# і для OpenAI-сумісного HTTP TTS API :8000).
resource "kubernetes_service" "holos_tts" {
  metadata {
    name      = "holos-tts"
    namespace = "default"
    annotations = {
      "metallb.universe.tf/loadBalancerIPs" = "192.168.0.47"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["metallb.io/ip-allocated-from-pool"],
    ]
  }
  spec {
    type = "LoadBalancer"
    selector = {
      app = "holos-tts"
    }
    port {
      name        = "wyoming"
      port        = 10200
      target_port = 10200
      protocol    = "TCP"
    }
    port {
      name        = "http"
      port        = 8000
      target_port = 8000
      protocol    = "TCP"
    }
  }
}
