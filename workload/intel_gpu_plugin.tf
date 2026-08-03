resource "helm_release" "intel_device_plugins_operator" {
  name             = "intel-device-plugins-operator"
  repository       = "https://intel.github.io/helm-charts"
  chart            = "intel-device-plugins-operator"
  namespace        = "kube-system"
  create_namespace = false
  version          = "0.30.0"
}

resource "helm_release" "intel_gpu_plugin" {
  name             = "intel-gpu-plugin"
  repository       = "https://intel.github.io/helm-charts"
  chart            = "intel-device-plugins-gpu"
  namespace        = "kube-system"
  create_namespace = false
  version          = "0.30.0"

  depends_on = [helm_release.intel_device_plugins_operator]

  values = [
    yamlencode({
      nodeFeatureRule = false
      sharedDevNum    = 5
    })
  ]
}
