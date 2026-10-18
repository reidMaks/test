resource "helm_release" "esphome" {
  name            = "esphome"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = local.app_template_version
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/esphome.yaml")
  ]
}
