resource "helm_release" "qnap_sync" {
  name            = "qnap-sync"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = local.app_template_version
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/qnap_sync.yaml")
  ]
}
