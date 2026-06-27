# ==========================================
# METALLB LOAD BALANCER
# ==========================================
resource "helm_release" "metallb" {
  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  namespace        = "metallb-system"
  create_namespace = true
  version          = "0.16.1"
}

# Застосовуємо наш локальний чарт з IP-пулами ПІСЛЯ встановлення MetalLB
resource "helm_release" "metallb_config" {
  name       = "metallb-config"
  chart      = "${path.module}/metallb-config"
  namespace  = "metallb-system"
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
