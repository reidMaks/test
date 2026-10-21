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
    MINIO_ROOT_USER                      = "admin"
    MINIO_ROOT_PASSWORD                  = data.bitwarden-secrets_secret.minio_root.value
    RUSTFS_ACCESS_KEY                    = "admin"
    RUSTFS_SECRET_KEY                    = data.bitwarden-secrets_secret.minio_root.value
    RUSTFS_IDENTITY_OPENID_CLIENT_SECRET = random_password.authentik_rustfs_secret.result
  }
}

resource "helm_release" "minio" {
  name            = "minio"
  repository      = "https://bjw-s-labs.github.io/helm-charts"
  chart           = "app-template"
  version         = local.app_template_version
  namespace       = "default"
  upgrade_install = true

  values = [
    yamlencode({
      defaultPodOptions = {
        annotations = {
          "checksum/secret" = sha256(jsonencode(kubernetes_secret.minio_secret.data))
        }
        nodeSelector = {
          "kubernetes.io/hostname" = "talos-cp-oci"
        }
        hostAliases = [
          {
            ip        = "192.168.0.45"
            hostnames = ["auth.kms-lab.in.ua"]
          }
        ]
      }
      controllers = {
        main = {
          type = "statefulset"

          containers = {
            main = {
              image = {
                repository = "rustfs/rustfs"
                tag        = "1.0.0"
              }
              # The volume holds files and .minio.sys written by MinIO as root (0:0);
              # RustFS reads them in-place and runs as root to keep them writable.
              securityContext = {
                runAsUser  = 0
                runAsGroup = 0
              }
              envFrom = [
                { secretRef = { name = kubernetes_secret.minio_secret.metadata[0].name } }
              ]
              env = {
                RUSTFS_VOLUMES                      = "/data"
                RUSTFS_ADDRESS                      = "0.0.0.0:9000"
                RUSTFS_CONSOLE_ENABLE               = "true"
                RUSTFS_CONSOLE_ADDRESS              = "0.0.0.0:9001"
                RUSTFS_CORS_ALLOWED_ORIGINS         = "*"
                RUSTFS_CONSOLE_CORS_ALLOWED_ORIGINS = "*"
                # Empty log directory instructs entrypoint.sh to stream logs to stdout
                # instead of writing to container-local /logs.
                RUSTFS_OBS_LOG_DIRECTORY = ""
                RUSTFS_OBS_LOGGER_LEVEL  = "warn"
                # Native OpenID Connect (OIDC) SSO with Authentik
                RUSTFS_BROWSER_REDIRECT_URL                 = "https://s3-ui.kms-lab.in.ua"
                RUSTFS_OUTBOUND_ALLOW_ORIGINS               = "https://auth.kms-lab.in.ua"
                RUSTFS_IDENTITY_OPENID_ENABLE               = "on"
                RUSTFS_IDENTITY_OPENID_CONFIG_URL           = "https://auth.kms-lab.in.ua/application/o/s3-ui/.well-known/openid-configuration"
                RUSTFS_IDENTITY_OPENID_ISSUER               = "https://auth.kms-lab.in.ua/application/o/s3-ui/"
                RUSTFS_IDENTITY_OPENID_CLIENT_ID            = "rustfs"
                RUSTFS_IDENTITY_OPENID_SCOPES               = "openid,profile,email"
                RUSTFS_IDENTITY_OPENID_REDIRECT_URI         = "https://s3-ui.kms-lab.in.ua/rustfs/admin/v3/oidc/callback/default"
                RUSTFS_IDENTITY_OPENID_REDIRECT_URI_DYNAMIC = "off"
                RUSTFS_IDENTITY_OPENID_DISPLAY_NAME         = "Authentik"
                RUSTFS_IDENTITY_OPENID_EMAIL_CLAIM          = "email"
                RUSTFS_IDENTITY_OPENID_USERNAME_CLAIM       = "preferred_username"
                RUSTFS_IDENTITY_OPENID_ROLE_POLICY          = "consoleAdmin"
              }
              probes = {
                readiness = {
                  enabled = true
                  custom  = true
                  spec = {
                    httpGet = {
                      path = "/health"
                      port = 9000
                    }
                    initialDelaySeconds = 10
                    periodSeconds       = 10
                    timeoutSeconds      = 5
                    failureThreshold    = 3
                  }
                }
                liveness = {
                  enabled = true
                  custom  = true
                  spec = {
                    httpGet = {
                      path = "/health"
                      port = 9000
                    }
                    initialDelaySeconds = 30
                    periodSeconds       = 15
                    timeoutSeconds      = 5
                    failureThreshold    = 3
                  }
                }
              }
              resources = {
                requests = {
                  cpu    = "50m"
                  memory = "384Mi"
                }
                limits = {
                  memory = "1Gi"
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
          annotations = {
            "gatus.home-operations.com/endpoint" = yamlencode({
              path = "/health"
            })
          }
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
          annotations = {
            "gatus.home-operations.com/endpoint" = yamlencode({
              path = "/health"
            })
          }
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

  depends_on = [
    helm_release.authentik
  ]
}
