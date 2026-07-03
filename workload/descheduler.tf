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
        strategies = {
          LowNodeUtilization = {
            enabled = true
            params = {
              nodeResourceUtilizationThresholds = {
                useDeviationThresholds = true
                thresholds = {
                  pods = 15
                }
                targetThresholds = {
                  pods = 15
                }
              }
            }
          }
        }
      }
    })
  ]
}
