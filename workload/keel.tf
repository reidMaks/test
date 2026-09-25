# ==============================================================================
# Keel: Automated Kubernetes Deployment Updates
# Monitors image registries (such as GHCR) and updates workloads automatically
# ==============================================================================

resource "helm_release" "keel" {
  name            = "keel"
  repository      = "https://charts.keel.sh"
  chart           = "keel"
  version         = "1.2.2"
  namespace       = "kube-system"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/keel.yaml")
  ]
}
