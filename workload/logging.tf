# ==========================================
# VICTORIA LOGS (Log Aggregation) & PROMTAIL
# ==========================================

resource "helm_release" "victorialogs" {
  name            = "vlogs"
  repository      = "https://victoriametrics.github.io/helm-charts/"
  chart           = "victoria-logs-single"
  namespace       = kubernetes_namespace.monitoring.metadata[0].name
  upgrade_install = true

  values = [
    yamlencode({
      server = {
        retentionPeriod = "3d" # Зберігати логи 3 дні (замість 7)
        persistentVolume = {
          enabled          = true
          size             = "2Gi"
          storageClassName = "longhorn"
        }
      }
    })
  ]
}

resource "helm_release" "promtail" {
  name            = "promtail"
  repository      = "https://grafana.github.io/helm-charts"
  chart           = "promtail"
  namespace       = kubernetes_namespace.monitoring.metadata[0].name
  upgrade_install = true

  values = [
    yamlencode({
      config = {
        clients = [
          {
            url = "http://vlogs-victoria-logs-single-server.monitoring.svc.cluster.local:9428/insert/loki/api/v1/push"
          }
        ]
        snippets = {
          pipelineStages = [
            {
              drop = {
                expression = ".*Uptime-Kuma.*|.*DEBUG: ci has 7 accounts.*|.*DEBUG: Found acc_info.*|.*DEBUG: Looking for acc_id.*|.*info: POST 200 /sync/sync.*"
              }
            },
            {
              match = {
                selector            = "{namespace=~\"kube-system|longhorn-system\"}"
                action              = "drop"
                drop_counter_reason = "drop_system_namespaces"
              }
            }
          ]
        }
      }
    })
  ]

  depends_on = [helm_release.victorialogs]
}
