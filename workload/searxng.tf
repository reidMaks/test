# ==========================================
# SEARXNG (via Helm Chart)
# ==========================================

resource "helm_release" "searxng" {
  name       = "searxng"
  repository = "https://charts.kubito.dev"
  chart      = "searxng"
  namespace  = "default"
  upgrade_install = true

  values = [
    yamlencode({
      ingress = {
        enabled   = true
        className = "traefik"
        hosts = [
          {
            host = "searxng.kms-lab.in.ua"
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
              }
            ]
          }
        ]
      }
      
      # Вмикаємо внутрішній Redis/Valkey
      redis = {
        enabled = true
      }
      
      searxng = {
        # Базова URL-адреса
        base_url = "https://searxng.kms-lab.in.ua"
      }
    })
  ]
}
