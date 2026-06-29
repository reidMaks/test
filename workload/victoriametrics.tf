# ==========================================
# VICTORIA METRICS (Metrics & Monitoring)
# ==========================================

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

data "bitwarden-secrets_secret" "grafana_admin_password" {
  id = "16c8b4c0-7dfb-4670-bb98-b478007a2af4"
}

resource "kubernetes_secret" "grafana" {
  metadata {
    name      = "grafana-secrets"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    admin-user     = "admin"
    admin-password = data.bitwarden-secrets_secret.grafana_admin_password.value
  }
}

resource "helm_release" "victoriametrics" {
  name            = "vm"
  repository      = "https://victoriametrics.github.io/helm-charts/"
  chart           = "victoria-metrics-k8s-stack"
  namespace       = kubernetes_namespace.monitoring.metadata[0].name
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/victoriametrics.yaml")
  ]

  depends_on = [kubernetes_secret.grafana]
}
