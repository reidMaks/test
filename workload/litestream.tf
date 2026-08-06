# ==========================================
# Shared Litestream configurations
# ==========================================

resource "kubernetes_secret" "litestream_s3" {
  metadata {
    name      = "litestream-s3"
    namespace = "default"
  }
  data = {
    MINIO_ACCESS_KEY = data.bitwarden-secrets_secret.minio_s3_access_key.value
    MINIO_SECRET_KEY = data.bitwarden-secrets_secret.minio_s3_secret_key.value
    QNAP_ACCESS_KEY  = data.bitwarden-secrets_secret.qobject_access_key.value
    QNAP_SECRET_KEY  = data.bitwarden-secrets_secret.qobject_secret_key.value
  }
}

resource "kubernetes_manifest" "vmpodscrape_litestream" {
  manifest = {
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMPodScrape"
    metadata = {
      name      = "litestream-metrics"
      namespace = "monitoring"
    }
    spec = {
      podMetricsEndpoints = [
        {
          port = "metrics"
        }
      ]
      selector = {
        matchLabels = {
          "litestream-metrics" = "true"
        }
      }
      namespaceSelector = {
        any = true
      }
    }
  }
}
