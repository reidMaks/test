data "bitwarden-secrets_secret" "cloudflared_token" {
  id = "b7cd56b0-df04-43bd-8bbd-b47700ad43ea"
}

resource "kubernetes_secret" "cloudflared" {
  metadata {
    name      = "cloudflared-secrets"
    namespace = "default"
  }

  data = {
    TUNNEL_TOKEN = data.bitwarden-secrets_secret.cloudflared_token.value
  }
}

resource "helm_release" "cloudflared" {
  name            = "cloudflared"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/cloudflared.yaml")
  ]

  depends_on = [kubernetes_secret.cloudflared]
}
