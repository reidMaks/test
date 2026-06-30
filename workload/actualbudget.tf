data "bitwarden-secrets_secret" "monobank_token" {
  id = "3f16903e-c45e-47b6-9716-b478016cd900"
}

resource "helm_release" "actualbudget" {
  name            = "actualbudget"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    templatefile("${path.module}/actualbudget/values.yaml", {
      addon_py       = file("${path.module}/actualbudget/addon.py")
      monobank_token = data.bitwarden-secrets_secret.monobank_token.value
    })
  ]
}
