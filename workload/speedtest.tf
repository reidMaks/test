# ==========================================
# SPEEDTEST (via Helm Chart)
# ==========================================

resource "helm_release" "speedtest" {
  name            = "speedtest"
  repository      = "https://openspeedtest.github.io/Helm-chart/"
  chart           = "openspeedtest"
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/speedtest.yaml")
  ]
}
