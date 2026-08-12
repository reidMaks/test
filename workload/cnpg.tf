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

  lifecycle {
    prevent_destroy = true
  }

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

      postgresql = {
        # NOTE: setting spec.postgresql.parameters at all triggers CNPG's
        # mutating webhook to inject its own inferred defaults (archive_mode,
        # wal_level, shared_preload_libraries, etc.) into this same map. The
        # kubernetes_manifest provider then sees those as an unexpected diff
        # after apply ("Provider produced inconsistent result") and errors,
        # even though the change itself does take effect. Listing CNPG's
        # defaults explicitly here (captured via `kubectl get cluster
        # shared-db -o jsonpath='{.spec.postgresql.parameters}'` after the
        # webhook ran once) keeps declared and live state in sync so future
        # applies are clean.
        parameters = {
          archive_mode               = "on"
          archive_timeout            = "5min"
          dynamic_shared_memory_type = "posix"
          full_page_writes           = "on"
          # OpenWebUI has left connections idle-in-transaction for 3+ hours
          # (a document_chunk SELECT that never commits/rolls back) -- these
          # hold back the vacuum xmin horizon and WAL recycling, the same
          # mechanism behind the earlier WAL-bloat incident, just a
          # different root cause (app-level leak, not replica divergence).
          # No default timeout existed to reclaim them. 10 minutes is long
          # enough for legitimate slow work, short enough to bound the leak.
          idle_in_transaction_session_timeout = "600000"
          log_destination                     = "csvlog"
          log_directory                       = "/controller/log"
          log_filename                        = "postgres"
          log_rotation_age                    = "0"
          log_rotation_size                   = "0"
          log_truncate_on_rotation            = "false"
          logging_collector                   = "on"
          max_parallel_workers                = "32"
          max_replication_slots               = "32"
          max_worker_processes                = "32"
          shared_memory_type                  = "mmap"
          shared_preload_libraries            = ""
          ssl_max_protocol_version            = "TLSv1.3"
          ssl_min_protocol_version            = "TLSv1.3"
          wal_keep_size                       = "512MB"
          wal_level                           = "logical"
          wal_log_hints                       = "on"
          wal_receiver_timeout                = "5s"
          wal_sender_timeout                  = "5s"
        }
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
