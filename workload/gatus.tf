data "bitwarden-secrets_secret" "gatus_ntfy_topic" {
  id = "ec5b6dd0-bead-4991-a0e7-b494013a4910"
}

resource "kubernetes_secret" "gatus_secrets" {
  metadata {
    name      = "gatus-secrets"
    namespace = "default"
  }

  data = {
    NTFY_TOPIC = data.bitwarden-secrets_secret.gatus_ntfy_topic.value
  }
}

resource "kubernetes_config_map" "gatus_config" {
  metadata {
    name      = "gatus-config"
    namespace = "default"
  }

  data = {
    "config.yaml" = file("${path.module}/gatus_config.yaml")
  }
}

resource "kubernetes_role" "gatus_sidecar" {
  metadata {
    name      = "gatus-sidecar"
    namespace = "default"
  }

  rule {
    api_groups = ["", "networking.k8s.io", "traefik.io"]
    resources  = ["services", "ingresses", "endpoints", "ingressroutes"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding" "gatus_sidecar" {
  metadata {
    name      = "gatus-sidecar"
    namespace = "default"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.gatus_sidecar.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "gatus"
    namespace = "default"
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

  depends_on = [kubernetes_config_map.gatus_config, kubernetes_secret.gatus_secrets, kubernetes_role_binding.gatus_sidecar]
}
