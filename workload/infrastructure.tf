# ==========================================
# METALLB LOAD BALANCER
# ==========================================
resource "kubernetes_namespace" "metallb_system" {
  metadata {
    name = "metallb-system"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "helm_release" "metallb" {
  name            = "metallb"
  repository      = "https://metallb.github.io/metallb"
  chart           = "metallb"
  namespace       = "metallb-system"
  version         = "0.16.1"
  upgrade_install = true
  depends_on      = [kubernetes_namespace.metallb_system]

  # Значення нижче виміряні через `kubectl top pod --containers -n metallb-system`
  # (frrk8s.enabled=true за замовчуванням -- саме frr-k8s DaemonSet, а не
  # legacy speaker.frr, несе основне навантаження BGP-стеку).
  values = [
    yamlencode({
      controller = {
        resources = {
          requests = { cpu = "20m", memory = "64Mi" }
          limits   = { memory = "128Mi" }
        }
      }
      speaker = {
        resources = {
          requests = { cpu = "10m", memory = "32Mi" }
          limits   = { memory = "128Mi" }
        }
      }
      "frr-k8s" = {
        frrk8s = {
          resources = {
            requests = { cpu = "20m", memory = "64Mi" }
            limits   = { memory = "160Mi" }
          }
          frr = {
            resources = {
              requests = { cpu = "10m", memory = "32Mi" }
              limits   = { memory = "128Mi" }
            }
          }
          frrMetrics = {
            resources = {
              requests = { cpu = "10m", memory = "16Mi" }
              limits   = { memory = "64Mi" }
            }
          }
          frrStatus = {
            resources = {
              requests = { cpu = "10m", memory = "16Mi" }
              limits   = { memory = "64Mi" }
            }
          }
          reloader = {
            resources = {
              requests = { cpu = "10m", memory = "16Mi" }
              limits   = { memory = "32Mi" }
            }
          }
        }
      }
    })
  ]
}

# Застосовуємо наш локальний чарт з IP-пулами ПІСЛЯ встановлення MetalLB
resource "helm_release" "metallb_config" {
  name            = "metallb-config"
  chart           = "${path.module}/metallb-config"
  namespace       = "metallb-system"
  upgrade_install = true
  depends_on      = [helm_release.metallb]
}

# ==========================================
# TRAEFIK INGRESS CONTROLLER
# ==========================================
resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://helm.traefik.io/traefik"
  chart            = "traefik"
  namespace        = "traefik-system"
  create_namespace = true
  version          = "42.1.3"
  upgrade_install  = true
  depends_on       = [helm_release.metallb_config]

  values = [
    yamlencode({
      providers = {
        kubernetesCRD     = { enabled = true, allowCrossNamespace = true }
        kubernetesIngress = { enabled = true }
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "100Mi"
        }
        limits = {
          memory = "300Mi"
        }
      }
      nodeSelector = {
        "topology.kubernetes.io/zone" = "oci"
      }
      service = {
        type = "LoadBalancer"
        annotations = {
          "metallb.universe.tf/loadBalancerIPs" = "192.168.0.45"
        }
      }
      ports = {
        web = {
          forwardedHeaders = {
            trustedIPs = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
          }
        }
        websecure = {
          forwardedHeaders = {
            trustedIPs = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
          }
        }
        git-ssh = {
          port        = 2222
          expose      = { default = true }
          exposedPort = 22
          protocol    = "TCP"
        }
      }
      ingressRoute = {
        dashboard = {
          enabled     = true
          matchRule   = "Host(`traefik.kms-lab.in.ua`)"
          entryPoints = ["web", "websecure"]
          middlewares = [
            {
              name      = "authentik-forwardauth"
              namespace = "default"
            }
          ]
        }
      }
    })
  ]
}

# ==========================================
# LONGHORN STORAGE
# ==========================================
resource "kubernetes_namespace" "longhorn_system" {
  metadata {
    name = "longhorn-system"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

data "bitwarden-secrets_secret" "qobject_access_key" {
  id = "6cdb37ca-5ec5-4ab6-8608-b478007ac01a"
}

data "bitwarden-secrets_secret" "qobject_secret_key" {
  id = "88f6f448-ebc1-44f5-87a7-b478007af8f1"
}

resource "kubernetes_secret" "longhorn_backup" {
  metadata {
    name      = "longhorn-backup-credential-v2"
    namespace = kubernetes_namespace.longhorn_system.metadata[0].name
  }

  data = {
    AWS_ACCESS_KEY_ID     = "admin"
    AWS_SECRET_ACCESS_KEY = data.bitwarden-secrets_secret.minio_root.value
    AWS_ENDPOINTS         = local.minio_s3_endpoint
    VIRTUAL_HOSTED_STYLE  = "false"
  }
}


resource "helm_release" "longhorn" {
  name            = "longhorn"
  repository      = "https://charts.longhorn.io"
  chart           = "longhorn"
  namespace       = "longhorn-system"
  version         = "1.12.1"
  upgrade_install = true

  depends_on = [
    kubernetes_namespace.longhorn_system,
    kubernetes_secret.longhorn_backup
  ]
  values = [
    yamlencode({
      defaultBackupStore = {
        backupTarget                 = "s3://kms-lab-data@us-east-1/longhorn-backups"
        backupTargetCredentialSecret = "longhorn-backup-credential-v2"
      }
      defaultSettings = {
        storageMinimalAvailablePercentage = 15
        defaultDataPath                   = "/var/lib/longhorn"
        backupTargetCredentialSecret      = "longhorn-backup-credential-v2"
        backupTarget                      = "s3://kms-lab-data@us-east-1/longhorn-backups"
        nodeDownPodDeletionPolicy         = "delete-pod-when-node-down"
        # У термінології Longhorn "Soft Anti-Affinity = true" означає ДОЗВОЛИТИ
        # розміщення кількох реплік в одній зоні (home), коли в іншій зоні (oci)
        # шедулінг вимкнено (allowScheduling: false). Значення "false" умикає
        # ЖОРСТКУ (Hard) анти-афінність і забороняє 2 репліки всередині home!
        replicaZoneSoftAntiAffinity                  = "true"
        defaultDataLocality                          = "best-effort"
        replicaAutoBalance                           = "best-effort"
        concurrentAutomaticEngineUpgradePerNodeLimit = 1
      }
      persistence = {
        defaultClassReplicaCount = 2
        defaultDataLocality      = "best-effort"
      }
    })
  ]
}

# ==========================================
# LONGHORN INGRESS
# ==========================================
resource "kubernetes_ingress_v1" "longhorn_ui" {
  metadata {
    name      = "longhorn-ui"
    namespace = "longhorn-system"
    annotations = {
      "traefik.ingress.kubernetes.io/router.middlewares" = "default-authentik-forwardauth@kubernetescrd"
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "longhorn.kms-lab.in.ua"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "longhorn-frontend"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.longhorn,
    helm_release.traefik
  ]
}

# ==========================================
# METRICS SERVER (for k9s CPU/RAM)
# ==========================================
resource "helm_release" "metrics_server" {
  name            = "metrics-server"
  repository      = "https://kubernetes-sigs.github.io/metrics-server/"
  chart           = "metrics-server"
  namespace       = "kube-system"
  version         = "3.14.0"
  upgrade_install = true

  values = [
    yamlencode({
      args = ["--kubelet-insecure-tls"]
      # Чарт вже задає request 100m/200Mi за замовчуванням (kubectl top: ~51Mi
      # реально) -- фіксуємо явно і додаємо відсутній memory limit.
      resources = {
        requests = { cpu = "100m", memory = "200Mi" }
        limits   = { memory = "400Mi" }
      }
    })
  ]
}

# ==========================================
# LONGHORN RECURRING JOBS
# ==========================================
resource "kubernetes_manifest" "longhorn_daily_backup" {
  manifest = {
    apiVersion = "longhorn.io/v1beta2"
    kind       = "RecurringJob"
    metadata = {
      name      = "daily-backup"
      namespace = "longhorn-system"
    }
    spec = {
      cron        = "0 2 * * *"
      task        = "backup"
      retain      = 7
      concurrency = 1
      groups      = ["daily-backups"]
    }
  }

  depends_on = [helm_release.longhorn]
}

# Longhorn CSI не копіює лейбли з Kubernetes PVC на внутрішні об'єкти
# volumes.longhorn.io, тому навішуємо мітку групи daily-backups напряму
# на Longhorn Volume CR для томів, які потребують бекапу в Google Drive.
data "kubernetes_persistent_volume_claim" "esphome_config" {
  metadata {
    name      = "esphome-config"
    namespace = "default"
  }
}

resource "kubernetes_labels" "longhorn_backup_esphome_config" {
  api_version = "longhorn.io/v1beta2"
  kind        = "Volume"
  metadata {
    name      = data.kubernetes_persistent_volume_claim.esphome_config.spec[0].volume_name
    namespace = kubernetes_namespace.longhorn_system.metadata[0].name
  }
  labels = {
    "recurring-job-group.longhorn.io/daily-backups" = "enabled"
  }

  depends_on = [
    helm_release.esphome,
    kubernetes_manifest.longhorn_daily_backup
  ]
}
