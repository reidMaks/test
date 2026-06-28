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

resource "helm_release" "victoriametrics" {
  name             = "vm"
  repository       = "https://victoriametrics.github.io/helm-charts/"
  chart            = "victoria-metrics-k8s-stack"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  upgrade_install  = true

  values = [
    file("${path.module}/helm_values/victoriametrics.yaml")
  ]
}
