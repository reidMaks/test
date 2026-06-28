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
  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  namespace        = "metallb-system"
  version          = "0.16.1"
  upgrade_install  = true
  depends_on       = [kubernetes_namespace.metallb_system]
}

# Застосовуємо наш локальний чарт з IP-пулами ПІСЛЯ встановлення MetalLB
resource "helm_release" "metallb_config" {
  name       = "metallb-config"
  chart      = "${path.module}/metallb-config"
  namespace  = "metallb-system"
  upgrade_install = true
  depends_on = [helm_release.metallb]
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
  version          = "41.0.0"
  upgrade_install  = true
  depends_on       = [helm_release.metallb_config]

  values = [
    yamlencode({
      providers = {
        kubernetesCRD     = { enabled = true }
        kubernetesIngress = { enabled = true }
      }
      service = {
        type = "LoadBalancer"
        annotations = {
          "metallb.universe.tf/loadBalancerIPs" = "192.168.0.45"
        }
      }
      ingressRoute = {
        dashboard = {
          enabled     = true
          matchRule   = "Host(`traefik.kms-lab.in.ua`)"
          entryPoints = ["web"]
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


resource "helm_release" "longhorn" {
  name       = "longhorn"
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  namespace  = "longhorn-system"
  version    = "1.12.0"
  upgrade_install = true

  depends_on = [kubernetes_namespace.longhorn_system]
  values = [
    yamlencode({
      defaultSettings = {
        defaultDataPath = "/var/lib/longhorn"
      }
      persistence = {
        defaultClassReplicaCount = 2
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
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.1"
  upgrade_install = true

  values = [
    yamlencode({
      args = ["--kubelet-insecure-tls"]
    })
  ]
}
