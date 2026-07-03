# ==========================================
# HEADLAMP - KUBERNETES WEB UI
# ==========================================
resource "kubernetes_namespace" "headlamp" {
  metadata {
    name = "headlamp"
  }
}

resource "helm_release" "headlamp" {
  name             = "headlamp"
  repository       = "https://kubernetes-sigs.github.io/headlamp/"
  chart            = "headlamp"
  namespace        = kubernetes_namespace.headlamp.metadata[0].name
  upgrade_install  = true

  values = [
    yamlencode({
      ingress = {
        enabled          = true
        ingressClassName = "traefik"
        hosts = [
          {
            host = "headlamp.kms-lab.in.ua"
            paths = [
              {
                path = "/"
                type = "Prefix"
              }
            ]
          }
        ]
      }
    })
  ]
}

# ==========================================
# ДОСТУП (Service Account та Token)
# ==========================================
# Створюємо Service Account для адміністрування
resource "kubernetes_service_account" "headlamp_admin" {
  metadata {
    name      = "headlamp-admin"
    namespace = kubernetes_namespace.headlamp.metadata[0].name
  }
}

# Даємо цьому акаунту права cluster-admin
resource "kubernetes_cluster_role_binding" "headlamp_admin" {
  metadata {
    name = "headlamp-admin-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.headlamp_admin.metadata[0].name
    namespace = kubernetes_namespace.headlamp.metadata[0].name
  }
}

# В нових версіях Kubernetes токени не створюються автоматично, тому робимо Secret
resource "kubernetes_secret" "headlamp_admin_token" {
  metadata {
    name      = "headlamp-admin-token"
    namespace = kubernetes_namespace.headlamp.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.headlamp_admin.metadata[0].name
    }
  }
  type = "kubernetes.io/service-account-token"
}
