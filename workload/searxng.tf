# ==========================================
# SEARXNG (via Helm Chart)
# ==========================================

resource "helm_release" "searxng" {
  name            = "searxng"
  repository      = "https://charts.kubito.dev"
  chart           = "searxng"
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/searxng.yaml")
  ]
}
