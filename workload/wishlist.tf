# ==========================================
# wishlist (via bjw-s app-template chart)
# ==========================================

resource "helm_release" "wishlist" {
  name            = "wishlist"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    file("${path.module}/helm_values/wishlist.yaml")
  ]
}
