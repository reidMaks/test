# ==========================================
# DIUN (Docker Image Update Notifier)
# ==========================================

resource "kubernetes_cluster_role" "diun" {
  metadata {
    name = "diun"
  }

  rule {
    api_groups = ["", "apps", "batch"]
    resources  = ["pods", "deployments", "statefulsets", "daemonsets", "cronjobs"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "diun" {
  metadata {
    name = "diun"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.diun.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "diun"
    namespace = "default"
  }
}

resource "helm_release" "diun" {
  name            = "diun"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/diun.yaml")
  ]

  depends_on = [kubernetes_cluster_role_binding.diun]
}
