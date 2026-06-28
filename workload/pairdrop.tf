# ==========================================
# PAIRDROP (via Helm Chart)
# ==========================================

resource "helm_release" "pairdrop" {
  name       = "pairdrop"
  repository = "https://charts.pascaliske.dev"
  chart      = "pairdrop"
  namespace  = "default"
  upgrade_install = true

  values = [
    yamlencode({
      ingressRoute = {
        create      = true
        entryPoints = ["web"]
        rule        = "Host(`pairdrop.kms-lab.in.ua`)"
      }
      
      env = [
        {
          name  = "WS_FALLBACK"
          value = "true"
        }
      ]
    })
  ]
}
