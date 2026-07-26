data "bitwarden-secrets_secret" "cf_dns_token" {
  id = "d2256848-eef6-411c-a864-b49300adc052"
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.14.4"
  namespace        = "cert-manager"
  create_namespace = true

  values = [
    yamlencode({
      installCRDs = true
    })
  ]
}

resource "kubernetes_secret" "cloudflare_api_token_secret" {
  metadata {
    name      = "cloudflare-api-token-secret"
    namespace = "cert-manager"
  }

  data = {
    "api-token" = data.bitwarden-secrets_secret.cf_dns_token.value
  }

  depends_on = [helm_release.cert_manager]
}

resource "helm_release" "cert_manager_resources" {
  name       = "cert-manager-resources"
  chart      = "${path.module}/cert-manager-resources"
  namespace  = "traefik-system"
  depends_on = [helm_release.cert_manager, kubernetes_secret.cloudflare_api_token_secret]
}
