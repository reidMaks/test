resource "helm_release" "descheduler" {
  name             = "descheduler"
  repository       = "https://kubernetes-sigs.github.io/descheduler/"
  chart            = "descheduler"
  namespace        = "kube-system"
  version          = "0.30.1"
  upgrade_install  = true

  values = [
    yamlencode({
      kind     = "CronJob"
      schedule = "*/15 * * * *"

      deschedulerPolicy = {
        apiVersion = "descheduler/v1alpha2"
        kind       = "DeschedulerPolicy"
        profiles = [
          {
            name = "default"
            pluginConfig = [
              {
                name = "LowNodeUtilization"
                args = {
                  useDeviationThresholds = true
                  thresholds = {
                    cpu    = 100
                    memory = 100
                    pods   = 15
                  }
                  targetThresholds = {
                    cpu    = 100
                    memory = 100
                    pods   = 15
                  }
                }
              }
            ]
            plugins = {
              balance = {
                enabled = ["LowNodeUtilization"]
              }
            }
          }
        ]
      }
    })
  ]
}
