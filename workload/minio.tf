data "bitwarden-secrets_secret" "minio_root" {
  id = "ad4f98dd-9f40-4717-bb00-b49d013fe11d"
}

resource "kubernetes_storage_class" "longhorn_oci_local" {
  metadata {
    name = "longhorn-oci-local"
  }
  storage_provisioner = "driver.longhorn.io"
  reclaim_policy      = "Retain"
  parameters = {
    numberOfReplicas    = "1"
    staleReplicaTimeout = "2880"
    fromBackup          = ""
    fsType              = "ext4"
    dataLocality        = "strict-local"
  }
}

resource "kubernetes_secret" "minio_secret" {
  metadata {
    name      = "minio-secret"
    namespace = "default"
  }
  data = {
    MINIO_ROOT_USER     = "admin"
    MINIO_ROOT_PASSWORD = data.bitwarden-secrets_secret.minio_root.value
  }
}

resource "helm_release" "minio" {
  name            = "minio"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    yamlencode({
      defaultPodOptions = {
        nodeSelector = {
          "kubernetes.io/hostname" = "talos-cp-oci"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9000"
          "prometheus.io/path"   = "/minio/v2/metrics/cluster"
        }
      }
      controllers = {
        main = {
          type = "statefulset"

          containers = {
            main = {
              image = {
                repository = "quay.io/minio/minio"
                tag        = "RELEASE.2024-03-30T09-41-56Z"
              }
              command = ["minio", "server", "/data", "--console-address", ":9001"]
              envFrom = [
                { secretRef = { name = kubernetes_secret.minio_secret.metadata[0].name } }
              ]
              env = {
                MINIO_PROMETHEUS_URL       = "http://vmsingle-vm-victoria-metrics-k8s-stack.monitoring.svc.cluster.local:8428"
                MINIO_PROMETHEUS_JOB_ID    = "minio"
                MINIO_PROMETHEUS_AUTH_TYPE = "public"
              }
              resources = {
                requests = {
                  cpu    = "50m"
                  memory = "128Mi"
                }
                limits = {
                  memory = "512Mi"
                }
              }
            }
          }
        }
      }
      service = {
        main = {
          controller = "main"
          ports = {
            api     = { port = 9000 }
            console = { port = 9001 }
          }
        }
      }
      persistence = {
        data = {
          type         = "persistentVolumeClaim"
          accessMode   = "ReadWriteOnce"
          size         = "45Gi"
          storageClass = kubernetes_storage_class.longhorn_oci_local.metadata[0].name
          advancedMounts = {
            main = {
              main = [
                { path = "/data" }
              ]
            }
          }
        }
      }
      ingress = {
        console = {
          enabled   = true
          className = "traefik"
          hosts = [
            {
              host = "s3-ui.kms-lab.in.ua"
              paths = [
                {
                  path = "/"
                  service = {
                    identifier = "main"
                    port       = "console"
                  }
                }
              ]
            }
          ]
        }
        api = {
          enabled   = true
          className = "traefik"
          hosts = [
            {
              host = "s3.kms-lab.in.ua"
              paths = [
                {
                  path = "/"
                  service = {
                    identifier = "main"
                    port       = "api"
                  }
                }
              ]
            }
          ]
        }
      }
    })
  ]
}

resource "kubernetes_manifest" "vmservicescrape_minio" {
  manifest = {
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "minio-metrics"
      namespace = "monitoring"
    }
    spec = {
      namespaceSelector = {
        matchNames = ["default"]
      }
      endpoints = [
        {
          port     = "api"
          path     = "/minio/v2/metrics/cluster"
          jobLabel = "app.kubernetes.io/name"
        }
      ]
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "minio"
        }
      }
    }
  }
}
