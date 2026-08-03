resource "kubernetes_namespace" "cnpg_system" {
  metadata {
    name = "cnpg-system"
  }
}

resource "helm_release" "cnpg" {
  name             = "cnpg"
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  namespace        = kubernetes_namespace.cnpg_system.metadata[0].name
  create_namespace = false
}

resource "kubernetes_storage_class" "longhorn_postgres" {
  metadata {
    name = "longhorn-postgres"
  }
  storage_provisioner = "driver.longhorn.io"
  reclaim_policy      = "Retain"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    numberOfReplicas    = "1"
    staleReplicaTimeout = "2880"
    dataLocality        = "strict-local"
  }
}

resource "kubernetes_manifest" "cnpg_catalog" {
  depends_on = [helm_release.cnpg]

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "ClusterImageCatalog"
    metadata = {
      name = "pg18-extensions"
    }
    spec = {
      images = [
        {
          major = 18
          # Чистий базовий образ PG18
          image = "ghcr.io/cloudnative-pg/postgresql:18.4-system-trixie"
          # Декларативне завантаження розширення pgvector через ImageVolume
          extensions = [
            {
              name = "pgvector"
              image = {
                reference = "ghcr.io/cloudnative-pg/postgres-extensions-containers/pgvector:18"
              }
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "cnpg_cluster" {
  depends_on = [helm_release.cnpg]

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = "shared-db"
      namespace = kubernetes_namespace.cnpg_system.metadata[0].name
    }
    spec = {
      instances = 3

      imageCatalogRef = {
        apiGroup = "postgresql.cnpg.io"
        kind     = "ClusterImageCatalog"
        name     = "pg18-extensions"
        major    = 18
      }

      storage = {
        size         = "20Gi"
        storageClass = kubernetes_storage_class.longhorn_postgres.metadata[0].name
      }
      affinity = {
        podAntiAffinityType = "required"
        nodeAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              preference = {
                matchExpressions = [
                  {
                    key      = "kubernetes.io/arch"
                    operator = "In"
                    values   = ["amd64"]
                  }
                ]
              }
            }
          ]
        }
      }
    }
  }
}

resource "kubernetes_config_map" "cnpg_grafana_dashboard" {
  metadata {
    name      = "cnpg-grafana-dashboard"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "cnpg-dashboard.json" = file("${path.module}/cnpg/grafana-dashboard.json")
  }
}

resource "kubernetes_manifest" "vmpodscrape_cnpg_cluster" {
  manifest = {
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMPodScrape"
    metadata = {
      name      = "cnpg-cluster-metrics"
      namespace = kubernetes_namespace.cnpg_system.metadata[0].name
    }
    spec = {
      podMetricsEndpoints = [
        {
          port = "metrics"
        }
      ]
      selector = {
        matchLabels = {
          "cnpg.io/cluster" = "shared-db"
        }
      }
    }
  }
}

resource "kubernetes_manifest" "vmpodscrape_cnpg_operator" {
  manifest = {
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMPodScrape"
    metadata = {
      name      = "cnpg-operator-metrics"
      namespace = kubernetes_namespace.cnpg_system.metadata[0].name
    }
    spec = {
      podMetricsEndpoints = [
        {
          port = "metrics"
        }
      ]
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "cloudnative-pg"
        }
      }
    }
  }
}
