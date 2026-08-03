resource "helm_release" "descheduler" {
  name            = "descheduler"
  repository      = "https://kubernetes-sigs.github.io/descheduler/"
  chart           = "descheduler"
  namespace       = "kube-system"
  version         = "0.30.1"
  upgrade_install = true

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
                    cpu    = 20
                    memory = 20
                    pods   = 20
                  }
                  targetThresholds = {
                    cpu    = 20
                    memory = 20
                    pods   = 20
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
