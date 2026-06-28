data "bitwarden-secrets_secret" "tandoor_db_password" {
  id = "2391cced-7e70-4ef1-a5d4-b4770084477e"
}

data "bitwarden-secrets_secret" "tandoor_fdc_api_key" {
  id = "ac2a25c3-0cc8-4062-9bb2-b47700849f84"
}

data "bitwarden-secrets_secret" "tandoor_secret_key" {
  id = "f228cbb7-5220-4678-a5bb-b4770083f01f"
}

resource "kubernetes_secret" "tandoor" {
  metadata {
    name      = "tandoor-secrets"
    namespace = "default"
  }

  data = {
    SECRET_KEY        = data.bitwarden-secrets_secret.tandoor_secret_key.value
    POSTGRES_PASSWORD = data.bitwarden-secrets_secret.tandoor_db_password.value
    FDC_API_KEY       = data.bitwarden-secrets_secret.tandoor_fdc_api_key.value
  }
}

resource "helm_release" "tandoor" {
  name            = "tandoor"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/tandoor.yaml")
  ]

  depends_on = [kubernetes_secret.tandoor]
}
