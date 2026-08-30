data "bitwarden-secrets_secret" "shared_redis" {
  id = "31fc311a-f2d1-4a61-afa9-b49b0077772d"
}

resource "kubernetes_secret" "shared_redis" {
  metadata {
    name      = "shared-redis-secrets"
    namespace = "default"
  }

  data = {
    REDIS_PASSWORD = data.bitwarden-secrets_secret.shared_redis.value
  }
}

resource "helm_release" "shared_redis" {
  name            = "shared-redis"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = "5.0.1"
  namespace       = "default"
  upgrade_install = true

  values = [
    yamlencode({
      controllers = {
        main = {
          type = "statefulset"
          containers = {
            main = {
              image = {
                repository = "redis"
                tag        = "7-alpine"
              }
              # maxmemory прив'язаний до нашого cgroup-ліміту (256Mi) нижче:
              # без нього Redis виділяє пам'ять без обмежень, доки cgroup
              # не вб'є процес, замість керованого evict по allkeys-lru.
              command = ["sh", "-c", "redis-server --requirepass $REDIS_PASSWORD --maxmemory 200mb --maxmemory-policy allkeys-lru"]
              envFrom = [
                { secretRef = { name = kubernetes_secret.shared_redis.metadata[0].name } }
              ]
              resources = {
                requests = {
                  cpu    = "20m"
                  memory = "64Mi"
                }
                limits = {
                  memory = "256Mi"
                }
              }
            }
            exporter = {
              image = {
                repository = "oliver006/redis_exporter"
                tag        = "v1.61.0"
              }
              env = [
                {
                  name  = "REDIS_ADDR"
                  value = "redis://localhost:6379"
                },
                {
                  name = "REDIS_PASSWORD"
                  valueFrom = {
                    secretKeyRef = {
                      name = kubernetes_secret.shared_redis.metadata[0].name
                      key  = "REDIS_PASSWORD"
                    }
                  }
                }
              ]
              resources = {
                requests = {
                  cpu    = "10m"
                  memory = "32Mi"
                }
                limits = {
                  memory = "64Mi"
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
            redis   = { port = 6379 }
            metrics = { port = 9121 }
          }
        }
      }
      persistence = {
        data = {
          type = "emptyDir"
          advancedMounts = {
            main = {
              main = [
                { path = "/data" }
              ]
            }
          }
        }
      }
    })
  ]
}

resource "kubernetes_manifest" "vmservicescrape_shared_redis" {
  manifest = {
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "shared-redis-metrics"
      namespace = "default"
    }
    spec = {
      endpoints = [
        {
          port = "metrics"
        }
      ]
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "shared-redis"
        }
      }
    }
  }
}
