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

      # Чарт вже задає requests за замовчуванням (500m/256Mi) -- явно фіксуємо
      # їх тут і додаємо memory limit, якого за замовчуванням немає.
      resources = {
        requests = { cpu = "500m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }

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
