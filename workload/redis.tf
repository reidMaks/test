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
              command = ["sh", "-c", "redis-server --requirepass $REDIS_PASSWORD"]
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
          }
        }
      }
      service = {
        main = {
          controller = "main"
          ports = {
            redis = { port = 6379 }
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
