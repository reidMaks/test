resource "kubernetes_config_map" "gatus_config" {
  metadata {
    name      = "gatus-config"
    namespace = "default"
  }

  data = {
    "config.yaml" = file("${path.module}/gatus_config.yaml")
  }
}

resource "helm_release" "gatus" {
  name            = "gatus"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/gatus.yaml")
  ]

  depends_on = [kubernetes_config_map.gatus_config]
}
