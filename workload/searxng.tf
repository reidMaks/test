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
    templatefile("${path.module}/helm_values/searxng.yaml", { redis_password = data.bitwarden-secrets_secret.shared_redis.value })
  ]
}
