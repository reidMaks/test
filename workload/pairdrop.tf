# ==========================================
# PAIRDROP (via Helm Chart)
# ==========================================

resource "helm_release" "pairdrop" {
  name            = "pairdrop"
  repository      = "https://charts.pascaliske.dev"
  chart           = "pairdrop"
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/pairdrop.yaml")
  ]
}
