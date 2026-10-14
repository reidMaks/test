resource "helm_release" "descheduler" {
  name            = "descheduler"
  repository      = "https://kubernetes-sigs.github.io/descheduler/"
  chart           = "descheduler"
  namespace       = "kube-system"
  version         = "0.36.0"
  upgrade_install = true

  values = [
    yamlencode({
      kind                       = "CronJob"
      schedule                   = "*/15 * * * *"
      successfulJobsHistoryLimit = 1
      failedJobsHistoryLimit     = 1

      # Зменшуємо requests для короткоживучого CronJob (реальне споживання мінімальне),
      # щоб сам Descheduler не завищував CPU requests на вузлі під час запуску.
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { memory = "128Mi" }
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
                  # Використовуємо абсолютні пороги замість відхилення від середнього,
                  # оскільки при useDeviationThresholds = true поріг pods (середнє 26.5% - 20% = 6.5%)
                  # був меншим за кількість DaemonSet-подів на вузлі (~9-15%), що блокувало балансування.
                  useDeviationThresholds = false
                  thresholds = {
                    cpu    = 35
                    memory = 35
                    pods   = 50
                  }
                  targetThresholds = {
                    cpu    = 65
                    memory = 65
                    pods   = 75
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
