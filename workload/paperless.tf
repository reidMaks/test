data "bitwarden-secrets_secret" "paperless_db_password" {
  id = "5c782528-6191-4718-a1bc-b4780128cdb2"
}

data "bitwarden-secrets_secret" "paperless_secret_key" {
  id = "be5332e6-a0fc-4d36-a2c9-b4780127d813"
}

resource "kubernetes_secret" "paperless" {
  metadata {
    name      = "paperless-secrets"
    namespace = "default"
  }

  data = {
    PAPERLESS_SECRET_KEY = data.bitwarden-secrets_secret.paperless_secret_key.value
    PAPERLESS_DBPASS     = data.bitwarden-secrets_secret.paperless_db_password.value
    POSTGRES_PASSWORD    = data.bitwarden-secrets_secret.paperless_db_password.value
  }
}

resource "helm_release" "paperless" {
  name            = "paperless"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/paperless.yaml")
  ]

  depends_on = [kubernetes_secret.paperless]
}
